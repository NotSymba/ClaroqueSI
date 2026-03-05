package warehouse;

import jason.asSyntax.*;
import jason.environment.Environment;
//import jason.environment.grid.Location;
import utils.Nodo;
import utils.Location;

import java.util.*;
import java.util.concurrent.*;
import java.util.stream.Collectors;

import javax.print.DocFlavor.STRING;

/**
 * Artefacto del almacén automatizado Proporciona la API para que los agentes
 * interactúen con el entorno
 */
public class WarehouseArtifact extends Environment {

    // Dimensiones del almacén
    private static final int GRID_WIDTH = 20;
    private static final int GRID_HEIGHT = 15;

    // GUI visual
    private WarehouseModel model;

    // Contadores para generar IDs
    private int containerCounter = 0;
    // Métricas
    private int totalContainersProcessed = 0;
    private int totalErrors = 0;
    private long startTime;

    private WarehouseView view;

    private ExecutorService containerGeneratorExecutor;
    private volatile boolean running = true;

    @Override
    public void init(String[] args) {
        super.init(args);
        // Inicializar modelo
        model = new WarehouseModel();

        view = new WarehouseView(model, GRID_WIDTH, GRID_HEIGHT);
        view.setVisible(true);

        // Mensaje de bienvenida en la consola
        view.logMessage("========================================");
        view.logMessage(" Warehouse Management System Initialized");
        view.logMessage("   Grid: " + GRID_WIDTH + "x" + GRID_HEIGHT);
        view.logMessage("   Robots: " + model.getRobots().size());
        view.logMessage("   Shelves: " + model.getShelves().size());
        view.logMessage("========================================");
        view.logMessage("");

        // Iniciar generador de contenedores
        startContainerGenerator();
        // Agregar shutdown hook para limpieza apropiada
        Runtime.getRuntime().addShutdownHook(new Thread(this::stop));
    }

    private void startContainerGenerator() {
        containerGeneratorExecutor = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "ContainerGenerator");
            t.setDaemon(true);
            return t;
        });

        containerGeneratorExecutor.submit(() -> {
            Random rand = new Random();
            while (running) {
                try {
                    Thread.sleep(5000 + rand.nextInt(5000)); // Entre 5 y 10 segundos

                    if (!running) {
                        break;
                    }

                    // Generar contenedor aleatorio
                    Container container = model.newContainer(); // Notificar al modelo para que actualice su estado

                    if (view != null) {
                        view.logMessage(String.format("New container: %s (%.1fkg, %s)",
                                container.getId(), container.getWeight(), container.getType()));
                        view.update();
                    }

                    /**
                     * *********************************************************************************************************
                     */
                    // Notificar a los agentes
                    addPercept(Literal.parseLiteral("new_container(\"" + container.getId() + "\")"));
                    /**
                     * *********************************************************************************************************
                     */

                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
            System.out.println("Container generator stopped");
        });
    }

    public void stop() {
        System.out.println("Stopping warehouse environment...");
        running = false;

        if (containerGeneratorExecutor != null) {
            containerGeneratorExecutor.shutdown();
            try {
                if (!containerGeneratorExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                    containerGeneratorExecutor.shutdownNow();
                }
            } catch (InterruptedException e) {
                containerGeneratorExecutor.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }

        System.out.println("Warehouse environment stopped");
    }

    //ESTO ES IMPORTANTE AQIO SE DEFINEN LAS ACCIONES QUE LOS AGENTES HACEN CON EL ENTORNO
    @Override
    public boolean executeAction(String agName, Structure action
    ) {
        try {
            String actionName = action.getFunctor();

            switch (actionName) {
                case "move_to":
                    return executeMoveTo(agName, action);
                case "pickup":
                    return executePickup(agName, action);
                case "drop_at":
                    return executeDropAt(agName, action);
                case "assignTask":
                    return ExecuteAssignTask(agName, action);
                case "get_container_info":
                    return executeGetContainerInfo(agName, action);
                case "get_free_shelf":
                    return executeGetFreeShelf(agName, action);
                //no lo vamos a usar
                /*
                    case "scan_surroundings":
                    return executeScanSurroundings(agName, action);
                 */

                case "taskcomplete":
                    return executeTaskComplete(agName, action);
                default:
                    System.err.println("Unknown action: " + actionName);
                    return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private boolean executeTaskComplete(String agName, Structure action) {
        String containerId = action.getTerm(0).toString().replace("\"", "");
        String shelfId = action.getTerm(1).toString().replace("\"", "");
        boolean correct = model.taskComplete(agName, action);

        if (correct) {
            addPercept(agName, Literal.parseLiteral("task_completed(\"" + containerId + "\",\"" + shelfId + "\")"));
            if (view != null) {
                view.logMessage(String.format("%s completed task for %s at %s", agName, containerId, shelfId));
                view.update();
            }
        } else {
            addError(agName, "task_complete_failed", "Failed to complete task for " + containerId);
        }
        return correct;
    }

    /**
     * Acción: move_to(X, Y) Mueve el robot a la posición especificada
     */
    private boolean executeMoveTo(String agName, Structure action) {
        int error = model.moveTo(agName, action);
        String destination = action.getTerm(0).toString();
        if (error == 0) {
            if (view != null) {
                view.logMessage(String.format("%s moving to %s", agName, destination));
                view.update();
            }
            updatePercepts();
            return true;
        } else if (error == 1) {
            if (view != null) {
                view.logMessage(String.format("invalid_destination: %s", destination));
                view.update();
            }
            addError(agName, "invalid_destination", "Unknown destination: " + action.getTerm(0).toString());
            return false;
        } else if (error == 2) {
            if (view != null) {
                view.logMessage(String.format("path_blocked: %s", destination));
                view.update();
            }
            addError(agName, "path_blocked", "No path to destination");
            return false;
        } else if (error == 3) {
            if (view != null) {
                view.logMessage(String.format("blocked_by_agent: %s", destination));
                view.update();
            }
            addError(agName, "blocked_by_agent", "Path blocked by another agent");
            return true; // El movimiento se intentó pero fue bloqueado, el agente puede decidir esperar o replanificar
        }
        return false;
    }

    /**
     * Acción: pickup(ContainerId) Recoge un contenedor
     */
    private boolean executePickup(String agName, Structure action) {
        int error = model.pickUp(agName, action);
        String containerId = action.getTerm(0).toString().replace("\"", "");
        if (error == 0) {
            if (view != null) {
                view.logMessage(String.format("🤖 %s picked up %s", agName, containerId));
                view.update();
            }
            removePerceptsByUnif(agName, Literal.parseLiteral("stored(_,_)"));
            addPercept(agName, Literal.parseLiteral("picked(\"" + containerId + "\")"));
            return true;
        } else if (error == 1) {

            addError(agName, "invalid_pick", "Robot or container not found");
        } else if (error == 2) {
            addError(agName, "already_carrying", "Robot is already carrying something");
        } else if (error == 3) {
            addError(agName, "too_far", "Container too far away");
        }
        return false;
    }
    /**
     * Acción: drop_at(ShelfId) Deposita el contenedor en una estantería
     */
    private boolean executeDropAt(String agName, Structure action) {
        String shelfId = action.getTerm(0).toString().replace("\"", "");
        int error = model.dropContainer(agName, action);

        if (error == 0) {
            if (view != null) {
                Robot robot = model.getRobots().get(agName);
                view.logMessage(String.format("%s stored %s at %s", agName, robot.getCarriedContainer().getId(), shelfId));
                view.update();
            }
            removePerceptsByUnif(agName, Literal.parseLiteral("carrying(_)"));
            addPercept(agName, Literal.parseLiteral("dropped(\"" + shelfId + "\")"));
            return true;
        } else if (error == 1) {
            addError(agName, "invalid_drop", "Robot or shelf not found");
        } else if (error == 2) {
            addError(agName, "not_carrying", "Robot is not carrying anything");
        } else if (error == 3) {
            addError(agName, "too_far", "Shelf too far away");
        } else if (error == 4) {
            addError(agName, "shelf_full", "Shelf " + shelfId + " cannot store container");
        }
        return false;
    }

    /**
     * Acción: request_task() Solicita una nueva tarea del scheduler
     */
    private boolean ExecuteAssignTask(String agName, Structure action) {
        String result = model.assignTask(agName, action);
        if ("error".equals(result)) {
            return false;
        } else if (result.equals("null")) {
            return false;
        } else if ("no_task".equals(result)) {
            addPercept(agName, Literal.parseLiteral("no_task"));
            return true;
        } else if ("cannot_carry".equals(result)) {
            addPercept(agName, Literal.parseLiteral("cannot_carry"));
            return true;
        } else if ("no_shelf_available".equals(result)) {
            addError(agName, "no_shelf_available", "No shelf available for container");
            return true;
        } else {
            if (view != null) {
                view.logMessage(String.format("%s assigned task: %s", agName, result.toString()));
                view.update();
            }
            addPercept(agName, Literal.parseLiteral(result));
            return true;
        }

    }

    /**
     * Acción: get_container_info(ContainerId) Obtiene información sobre un
     * contenedor
     */
    private boolean executeGetContainerInfo(String agName, Structure action) {
        Literal containerInfo = model.getContainerInfo(agName, action); // Implementar si es necesario
        if (containerInfo != null) {
            addPercept(agName, containerInfo);
            return true;
        } else {
            addError(agName, "container_not_found", action.getTerm(0).toString());
            return false;
        }
    }

    /**
     * Acción: get_free_shelf(ContainerId) Busca una estantería libre para un
     * contenedor
     */
    private boolean executeGetFreeShelf(String agName, Structure action) {
        Literal freeShelf = model.getFreeShelf(agName, action); // Implementar si es necesario
        if (freeShelf != null) {
            addPercept(agName, freeShelf);
            return true;
        }
        return false;
    }

    /**
     * Acción: scan_surroundings() Escanea las celdas alrededor del robot
     */
    /*No lo vamos a usar
    private boolean executeScanSurroundings(String agName, Structure action) {
        return model.scanSurroundings;
    }
     */
    /**
     * Agrega un error a las percepciones
     */
    private void addError(String agName, String errorType, String data) {
        totalErrors++;
        addPercept(agName, Literal.parseLiteral(
                "error(" + errorType + ",\"" + data + "\")"
        ));
        System.err.println("ERROR [" + agName + "]: " + errorType + " - " + data);
    }

    void updatePercepts() {
    }
    /*
    
     */

}
