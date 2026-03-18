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
    // Métricas
    private int totalErrors = 0;

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
                    if (container == null) {
                        addError("supervisor", "container_generation_failed", "Failed to generate new container");
                        continue; // Si no se pudo generar un contenedor, intentar de nuevo
                    }

                    if (view != null) {
                        view.logMessage(String.format("New container: %s (%.1fkg, %s)",
                                container.getId(), container.getWeight(), container.getType()));
                        view.update();
                    }
                    // Notificar al gentes
                    addPercept("scheduler",Literal.parseLiteral("new_container(\"" + container.getId() + "\")"));
                    addPercept("supervisor",Literal.parseLiteral("new_container(\"" + container.getId() + "\")"));



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
            removePerceptsByUnif(agName, Literal.parseLiteral("task(_,_)"));
            addPercept("scheduler", Literal.parseLiteral("task_completed(\"" + agName + "\",\"" + containerId + "\",\"" + shelfId + "\")"));
            viewAct(String.format("%s completed task for %s at %s", agName, containerId, shelfId));
        } else {
            addError(agName, "task_complete_failed", "Failed to complete task for " + containerId);
        }
        return correct;
    }

    /**
     * Acción: move_to(X, Y) Mueve el robot a la posición especificada
     */
    private boolean executeMoveTo(String agName, Structure action) {
        try {
            int error = model.moveTo(agName, action);
            String destination = action.getTerm(0).toString().replace("\"", "");
            if (error == 0) {
                viewAct(String.format("%s moved to %s", agName, destination));
                return true;
            } else if (error == 1) {
                addError(agName, "invalid_destination", "Unknown destination: " + destination);
                return false;
            } else if (error == 3) {
                addError(agName, "blocked_by_agent", "Path blocked by another agent");
                return true; // El movimiento se intentó pero fue bloqueado, el agente puede decidir esperar o replanificar
            }
            if (error == 5) {
                addError(agName, "splashContainer", "splash container error: ");
            } else {
                addError(agName, "uknown", "uknown error code: " + error);
            }
            return false;
        } finally {

            removePerceptsByUnif(agName, Literal.parseLiteral("at(_,_)"));
            updatePercepts();
        }

    }

    /**
     * Acción: pickup(ContainerId) Recoge un contenedor
     */
    private boolean executePickup(String agName, Structure action) {
        int error = model.pickUp(agName, action);
        String containerId = action.getTerm(0).toString().replace("\"", "");
        if (error == 0) {
            viewAct(String.format("%s picked up %s", agName, containerId));
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
        Robot robot = model.getRobots().get(agName);
        if (error == 0) {
            viewAct(String.format("%s dropped container at %s", agName, shelfId));
            removePerceptsByUnif(agName, Literal.parseLiteral("picked(_)"));
            return true;
        } else if (error == 1) {
            addError(agName, "invalid_drop", "Robot or shelf not found");
        } else if (error == 2) {
            addError(agName, "not_carrying", "Robot is not carrying anything");
            return true;
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
        } else if (result.equals("null_robot")) {
            return false;
        } else if (result.equals("null_container")) {
            return false;
        } else if (result.equals("already_assigned")) {
            return true;
        } else if ("no_task".equals(result)) {
            addPercept(agName, Literal.parseLiteral("no_task"));
            return true;
        } else if ("cannot_carry".equals(result)) {
            addError(agName, "cannot_carry", "this robot cannot carry the assigned container");
            return true;
        } else if ("no_shelf_available".equals(result)) {
            addError(agName, "no_shelf_available", "No shelf available for container");
            return true;
        } else {
            viewAct(String.format("%s assigned task: %s", agName, result.toString()));
            removePerceptsByUnif(agName, Literal.parseLiteral("no_task"));
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
            viewAct(String.format("%s requested info for %s: %s", agName, action.getTerm(0).toString(), containerInfo.toString()));
            addPercept(agName, containerInfo);
            return true;
        } else {
            viewAct(String.format("%s requested info for %s: not found", agName, action.getTerm(0).toString()));
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
     * Agrega un error a las percepciones
     */
    private void addError(String agName, String errorType, String data) {
        removePerceptsByUnif(agName, Literal.parseLiteral("error(_,_)"));
        addPercept(agName, Literal.parseLiteral(
                "error(" + errorType + ",\"" + data + "\")"
        ));
        System.err.println("ERROR [" + agName + "]: " + errorType + " - " + data);
        totalErrors++;
        addPercept("supervisor", Literal.parseLiteral("total_errors(" + errorType + "," + totalErrors + ")"));
    }

    //Espaguetis a la carbornara 
    void updatePercepts() {
        // Posiciones iniciales de los robots
        Map<String, String> initialPositions = Map.of(
                "lightInit", "lightInit",
                "mediumInit", "mediumInit",
                "heavyInit", "heavyInit"
        );

        // Estanterías
        List<String> shelves = List.of(
                "shelf_1", "shelf_2", "shelf_3", "shelf_4",
                "shelf_5", "shelf_6", "shelf_7", "shelf_8", "shelf_9"
        );
        // Actualizar percepciones de todos los robots
        for (Map.Entry<String, Robot> entry : model.getRobots().entrySet()) {
            String agName = entry.getKey();
            Robot robot = entry.getValue();
            Location loc = new Location(robot.getX(), robot.getY());

            // Verificar posiciones iniciales
            for (Map.Entry<String, String> init : initialPositions.entrySet()) {
                if (model.getLocation(init.getKey()).distance(loc) == 0) {
                    addPercept(agName, Literal.parseLiteral("at(" + robot.getId() + "," + init.getValue() + ")"));
                }
            }
            for (Container container : model.getContainers().values()) {
                if (model.getLocation(container.getId()).distance(loc) == 1) {
                    addPercept(agName, Literal.parseLiteral("at(" + robot.getId() + "," + container.getId() + ")"));
                }
            }
            // Verificar estanterías adyacentes
            for (String shelf : shelves) {
                if (model.isAdjacentToShelf(agName, shelf)) {
                    addPercept(agName, Literal.parseLiteral("at(" + robot.getId() + "," + shelf + ")"));
                }
            }
        }

    }

    private void viewAct(String message) {
        if (view != null) {
            view.logMessage(message);
            view.update();
        }
    }

}
