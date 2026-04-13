package warehouse;
 
import jason.asSyntax.*;
import jason.environment.Environment;
import utils.Location;
 
import java.util.*;
import java.util.concurrent.*;
 
public class WarehouseArtifact extends Environment {
 
    private static final int GRID_WIDTH = 20;
    private static final int GRID_HEIGHT = 15;
 
    private WarehouseModel model;
    private WarehouseView view;
 
    private int totalErrors = 0;
 
    private ExecutorService containerGeneratorExecutor;
    private volatile boolean running = true;
 
    @Override
    public void init(String[] args) {
        super.init(args);
 
        model = new WarehouseModel();
 
        view = new WarehouseView(model, GRID_WIDTH, GRID_HEIGHT);
        view.setVisible(true);
 
        view.logMessage("========================================");
        view.logMessage(" Warehouse Management System Initialized");
        view.logMessage("   Grid: " + GRID_WIDTH + "x" + GRID_HEIGHT);
        view.logMessage("   Robots: " + model.getRobots().size());
        view.logMessage("   Shelves: " + model.getShelves().size());
        view.logMessage("========================================");
        view.logMessage("");
 
        startContainerGenerator();
        Runtime.getRuntime().addShutdownHook(new Thread(this::stop));
    }
 
    // -------------------------------------------------------------------------
    // GENERADOR DE CONTENEDORES
    // -------------------------------------------------------------------------
 
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
                    Thread.sleep(5000 + rand.nextInt(5000));
 
                    if (!running) break;
 
                    Container container = model.newContainer();
                    if (container == null) {
                        addError("supervisor", "container_generation_failed", "Failed to generate new container");
                        continue;
                    }
 
                    if (view != null) {
                        view.logMessage(String.format("New container: %s (%.1fkg, %s)",
                                container.getId(), container.getWeight(), container.getType()));
                        view.update();
                    }
 
                    // Notificar a scheduler y supervisor, reemplazando percepción anterior
                    removePerceptsByUnif("scheduler", Literal.parseLiteral("new_container(_)"));
                    removePerceptsByUnif("supervisor", Literal.parseLiteral("new_container(_)"));
                    addPercept("scheduler", Literal.parseLiteral("new_container(\"" + container.getId() + "\")"));
                    addPercept("supervisor", Literal.parseLiteral("new_container(\"" + container.getId() + "\")"));
 
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
 
    // -------------------------------------------------------------------------
    // DISPATCH DE ACCIONES
    // -------------------------------------------------------------------------
 
    @Override
    public boolean executeAction(String agName, Structure action) {
        try {
            String actionName = action.getFunctor();
 
            switch (actionName) {
                case "steap":
                    return executeSteap(agName, action);
                case "pickup":
                    return executePickup(agName, action);
                case "drop_at":
                    return executeDropAt(agName, action);
                case "assignTask":
                    return executeAssignTask(agName, action);
                case "get_container_info":
                    return executeGetContainerInfo(agName, action);
                case "get_location":
                    return executeGetLocation(agName, action);
                case "get_shelf_status":
                    return executeGetShelfStatus(agName, action);
                case "task_complete":
                    return executeTaskComplete(agName, action);
                case "move_to_processing":
                    return executeMoveToProcessing(agName, action);
                default:
                    System.err.println("Unknown action: " + actionName);
                    return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }
 
    // -------------------------------------------------------------------------
    // IMPLEMENTACIÓN DE ACCIONES
    // -------------------------------------------------------------------------
 
    /**
     * Acción: steap(X, Y)
     * Mueve el robot un paso a la posición indicada.
     */
    private boolean executeSteap(String agName, Structure action) {
        try {
            int error = model.steap(agName, action);
            String destination = action.getTerm(0).toString() + "," + action.getTerm(1).toString();
 
            if (error == 0) {
                viewAct(String.format("%s moved to (%s)", agName, destination));
                return true;
            } else if (error == 3) {
                addError(agName, "blocked_by_agent", "Path blocked by another agent at " + destination);
                return true; // El agente puede replanificar
            } else if (error == 5) {
                addError(agName, "splash_container", "Robot stepped on a container at " + destination);
                return false;
            } else {
                addError(agName, "unknown", "Unknown error code: " + error);
                return false;
            }
        } finally {
            removePerceptsByUnif(agName, Literal.parseLiteral("at(_,_,_)"));
            updatePercepts(agName);
        }
    }
 
    /**
     * Acción: pickup(ContainerId)
     * Recoge un contenedor desde la zona de clasificación.
     */
    private boolean executePickup(String agName, Structure action) {
        String containerId = action.getTerm(0).toString().replace("\"", "");
        int error = model.pickUp(agName, action);
 
        if (error == 0) {
            viewAct(String.format("%s picked up %s", agName, containerId));
            addPercept(agName, Literal.parseLiteral("picked(\"" + containerId + "\")"));
            return true;
        } else if (error == 1) {
            addError(agName, "invalid_pick", "Robot or container not found: " + containerId);
        } else if (error == 2) {
            addError(agName, "already_carrying", "Robot is already carrying something");
        } else if (error == 3) {
            addError(agName, "too_far", "Container too far away: " + containerId);
        }
        return false;
    }
 
    /**
     * Acción: move_to_processing(ContainerId, DestX, DestY)
     * Mueve un paquete de la zona de entrada a la zona de clasificación.
     * Restaura la celda origen a ENTRANCE y marca la destino como PACKAGE.
     */
    private boolean executeMoveToProcessing(String agName, Structure action) {
        String containerId = action.getTerm(0).toString().replace("\"", "");
        int error = model.moveToProcessing(agName, action);
 
        if (error == 0) {
            viewAct(String.format("%s moved container %s to processing zone", agName, containerId));
            return true;
        } else if (error == 1) {
            addError(agName, "invalid_move", "Robot or container not found: " + containerId);
        } else if (error == 2) {
            addError(agName, "already_picked", "Container already picked or not in entrance: " + containerId);
        } else if (error == 3) {
            addError(agName, "dest_occupied", "Destination cell is not a free classification cell");
        } else if (error == 4) {
            addError(agName, "dest_out_of_bounds", "Destination is outside classification zone");
        } else {
            addError(agName, "unknown", "Unexpected error moving container " + containerId);
        }
        return false;
    }
 
    /**
     * Acción: drop_at(ShelfId)
     * Deposita el contenedor que lleva el robot en una estantería adyacente.
     */
    private boolean executeDropAt(String agName, Structure action) {
        String shelfId = action.getTerm(0).toString().replace("\"", "");
        int error = model.dropContainer(agName, action);
 
        if (error == 0) {
            viewAct(String.format("%s dropped container at %s", agName, shelfId));
            removePerceptsByUnif(agName, Literal.parseLiteral("picked(_)"));
            return true;
        } else if (error == 1) {
            addError(agName, "invalid_drop", "Robot or shelf not found: " + shelfId);
        } else if (error == 2) {
            addError(agName, "not_carrying", "Robot is not carrying anything");
            return true; // No es un error fatal, el agente puede continuar
        } else if (error == 3) {
            addError(agName, "too_far", "Shelf too far away: " + shelfId);
        } else if (error == 4) {
            addError(agName, "shelf_full", "Shelf " + shelfId + " cannot store container");
        }
        return false;
    }
 
    /**
     * Acción: assignTask(ContainerId, ShelfId)
     * Asigna una tarea de transporte al robot.
     */
    private boolean executeAssignTask(String agName, Structure action) {
        String result = model.assignTask(agName, action);
 
        switch (result) {
            case "error":
            case "null_robot":
            case "null_container":
                return false;
            case "already_assigned":
                return true;
            case "busy":
                addError(agName, "busy", "Robot is already busy or carrying");
                return true;
            case "no_task":
                addPercept(agName, Literal.parseLiteral("no_task"));
                return true;
            case "cannot_carry":
                addError(agName, "cannot_carry", "This robot cannot carry the assigned container");
                return true;
            case "null_shelf":
                addError(agName, "no_shelf_available", "No valid shelf for container");
                return true;
            default:
                viewAct(String.format("%s assigned task: %s", agName, result));
                removePerceptsByUnif(agName, Literal.parseLiteral("no_task"));
                addPercept(agName, Literal.parseLiteral(result));
                return true;
        }
    }
 
    /**
     * Acción: get_container_info(ContainerId)
     * Añade una percepción con el peso, dimensiones y tipo del contenedor.
     */
    private boolean executeGetContainerInfo(String agName, Structure action) {
        Literal containerInfo = model.getContainerInfo(agName, action);
        if (containerInfo != null) {
            viewAct(String.format("%s requested info for %s: %s",
                    agName, action.getTerm(0).toString(), containerInfo.toString()));
            addPercept(agName, containerInfo);
            return true;
        } else {
            addError(agName, "container_not_found", action.getTerm(0).toString());
            return false;
        }
    }
 
    /**
     * Acción: get_location(ItemId)
     * Añade una percepción location(ItemId, X, Y).
     */
    private boolean executeGetLocation(String agName, Structure action) {
        String itemId = action.getTerm(0).toString().replace("\"", "");
        Literal locationInfo = model.getLocation(itemId);
        if (locationInfo != null) {
            addPercept(agName, locationInfo);
            viewAct(String.format("%s location of %s: %s", agName, itemId, locationInfo.toString()));
            return true;
        } else {
            addError(agName, "item_not_found", "Item not found: " + itemId);
            return false;
        }
    }
 
    /**
     * Acción: get_shelf_status(ShelfId)
     * Añade una percepción shelf_info(ShelfId, MaxW, CurW, MaxV, CurV).
     */
    private boolean executeGetShelfStatus(String agName, Structure action) {
        Literal shelfInfo = model.get_shelf_status(agName, action);
        if (shelfInfo != null) {
            addPercept(agName, shelfInfo);
            return true;
        }
        addError(agName, "shelf_not_found", action.getTerm(0).toString());
        return false;
    }
 
    /**
     * Acción: task_complete(ContainerId, ShelfId)
     * Marca la tarea como completada y notifica al scheduler.
     */
    private boolean executeTaskComplete(String agName, Structure action) {
        String containerId = action.getTerm(0).toString().replace("\"", "");
        String shelfId = action.getTerm(1).toString().replace("\"", "");
        boolean correct = model.taskComplete(agName, action);
 
        if (correct) {
            removePerceptsByUnif(agName, Literal.parseLiteral("task(_,_)"));
            addPercept("scheduler", Literal.parseLiteral(
                    "task_completed(\"" + agName + "\",\"" + containerId + "\",\"" + shelfId + "\")"));
            viewAct(String.format("%s completed task for %s at %s", agName, containerId, shelfId));
        } else {
            addError(agName, "task_complete_failed", "Failed to complete task for " + containerId);
        }
        return correct;
    }
 
    // -------------------------------------------------------------------------
    // UTILIDADES
    // -------------------------------------------------------------------------
 
    /**
     * Actualiza la percepción de posición de un robot concreto.
     * Formato: at(RobotId, X, Y)
     */
    private void updatePercepts(String agName) {
        Robot robot = model.getRobots().get(agName);
        if (robot == null) return;
 
        removePerceptsByUnif(agName, Literal.parseLiteral("at(_,_,_)"));
        addPercept(agName, Literal.parseLiteral(
                "at(\"" + robot.getId() + "\"," + robot.getX() + "," + robot.getY() + ")"
        ));
    }
 
    private void addError(String agName, String errorType, String data) {
        removePerceptsByUnif(agName, Literal.parseLiteral("error(_,_)"));
        addPercept(agName, Literal.parseLiteral(
                "error(" + errorType + ",\"" + data + "\")"
        ));
        System.err.println("ERROR [" + agName + "]: " + errorType + " - " + data);
        totalErrors++;
        addPercept("supervisor", Literal.parseLiteral("total_errors(" + errorType + "," + totalErrors + ")"));
    }
 
    private void viewAct(String message) {
        if (view != null) {
            view.logMessage(message);
            view.update();
        }
    }
}
 