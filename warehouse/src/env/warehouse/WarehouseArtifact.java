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

                    if (!running) {
                        break;
                    }

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

                    updateOccupancy(container.getX(), container.getY(), true);
                    updateContainerAt(container.getId(), container.getX(), container.getY());

                    removePerceptsByUnif( Literal.parseLiteral("new_container(_)"));
                    addPercept(Literal.parseLiteral("new_container(\"" + container.getId() + "\")"));

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
                case "step":
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

                case "relocate_container":
                    return executeRelocateContainer(agName, action);

                case "see":
                    return executeSee(agName, action);

                case "get_shelf_adjacent":
                    return executeGetShelfAdjacent(agName, action);

                default:
                    System.err.println("Unknown action: " + actionName);
                    return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: see() Percibe entorno cercano (radio 1) teniendo en cuenta
     * objetos multi-celda.
     */
    private boolean executeSee(String agName, Structure action) {

        Robot robot = model.getRobots().get(agName);
        if (robot == null) {
            return false;
        }

        int rx = robot.getX();
        int ry = robot.getY();

        CellType[][] grid = model.getGrid();

        // Limpiar percepciones anteriores
        removePerceptsByUnif(agName, Literal.parseLiteral("shelf(_,_)"));
        removePerceptsByUnif(agName, Literal.parseLiteral("robot(_,_,_)"));
        removePerceptsByUnif(agName, Literal.parseLiteral("container(_,_,_)"));
        removePerceptsByUnif(agName, Literal.parseLiteral("at(_,_,_)"));
        addPercept(agName, Literal.parseLiteral(
                "at(" + agName + "," + rx + "," + ry + ")"
        ));
        //─────────────────────────────────────────
        //  VER CELDAS ALREDEDOR (radio Manhattan 1)
        // ─────────────────────────────────────────
        for (int dx = -1; dx <= 1; dx++) {
            for (int dy = -1; dy <= 1; dy++) {

                if (Math.abs(dx) + Math.abs(dy) > 1) {
                    continue;
                }

                int x = rx + dx;
                int y = ry + dy;

                // límites
                if (x < 0 || x >= GRID_WIDTH || y < 0 || y >= GRID_HEIGHT) {
                    continue;
                }

                // ───────── SHELVES (MULTI-CELDA) ─────────
                if (grid[x][y] == CellType.SHELF) {
                    addPercept(agName, Literal.parseLiteral(
                            "shelf(" + x + "," + y + ")"
                    ));
                }

                // ───────── CONTAINERS ─────────
                if (grid[x][y] == CellType.PACKAGE) {
                    // buscar qué contenedor está ahí
                    for (Container c : model.getContainers().values()) {
                        if (!c.isPicked() && c.getX() == x && c.getY() == y) {
                            addPercept(agName, Literal.parseLiteral(
                                    "container(\"" + c.getId() + "\"," + x + "," + y + ")"
                            ));
                            break;
                        }
                    }
                }
            }
        }

        // ───────── ROBOTS ─────────
        for (Robot r : model.getRobots().values()) {
            if (r.getId().equals(agName)) {
                continue;
            }

            int x = r.getX();
            int y = r.getY();

            if (Math.abs(rx - x) + Math.abs(ry - y) <= 1) {
                addPercept(agName, Literal.parseLiteral(
                        "robot(\"" + r.getId() + "\"," + x + "," + y + ")"
                ));
            }
        }

        return true;
    }

    private boolean executeSteap(String agName, Structure action) {
        try {
            int error = model.steap(agName, action);
            String destination = action.getTerm(0).toString() + "," + action.getTerm(1).toString();

            if (error == 0) {
                removePerceptsByUnif(agName, Literal.parseLiteral("error(_,_)"));
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
     * Acción: pickup(ContainerId) Recoge un contenedor desde la zona de
     * clasificación.
     */
    private boolean executePickup(String agName, Structure action) {
        String containerId = action.getTerm(0).toString().replace("\"", "");
        Container container = model.getContainers().get(containerId);
        int preX = container != null ? container.getX() : -1;
        int preY = container != null ? container.getY() : -1;
        int error = model.pickUp(agName, action);

        if (error == 0) {
            viewAct(String.format("%s picked up %s", agName, containerId));
            addPercept(agName, Literal.parseLiteral("picked(\"" + containerId + "\")"));
            updateOccupancy(preX, preY, false);
            removePerceptsByUnif("scheduler",
                    Literal.parseLiteral("container_at(\"" + containerId + "\",_,_)"));
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
     * Acción: move_to_processing(ContainerId, DestX, DestY) Mueve un paquete de
     * la zona de entrada a la zona de clasificación. Restaura la celda origen a
     * ENTRANCE y marca la destino como PACKAGE.
     */
    private boolean executeMoveToProcessing(String agName, Structure action) {
        String containerId = action.getTerm(0).toString().replace("\"", "");
        Container container = model.getContainers().get(containerId);
        int preX = container != null ? container.getX() : -1;
        int preY = container != null ? container.getY() : -1;
        int error = model.moveToProcessing(agName, action);

        if (error == 0) {
            viewAct(String.format("%s moved container %s to processing zone", agName, containerId));
            updateOccupancy(preX, preY, false);
            if (container != null) {
                updateOccupancy(container.getX(), container.getY(), true);
                updateContainerAt(containerId, container.getX(), container.getY());
            }
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
     * Acción: relocate_container(ContainerId, DestX, DestY) Mueve un paquete a
     * una celda libre de clasificación. El scheduler decide el destino.
     */
    private boolean executeRelocateContainer(String agName, Structure action) {
        String containerId = action.getTerm(0).toString().replace("\"", "");
        int srcX = -1, srcY = -1;
        Container container = model.getContainers().get(containerId);
        if (container != null) {
            srcX = container.getX();
            srcY = container.getY();
        }

        int error = model.relocateContainer(agName, action);

        if (error == 0) {
            viewAct(String.format("%s relocated container %s", agName, containerId));
            updateOccupancy(srcX, srcY, false);
            if (container != null) {
                updateOccupancy(container.getX(), container.getY(), true);
                updateContainerAt(containerId, container.getX(), container.getY());
                // Invalidar beliefs location/3 obsoletos y notificar a los
                // robots para que cualquier plan en curso se replantee.
                for (String robotName : model.getRobots().keySet()) {
                    removePerceptsByUnif(robotName,
                            Literal.parseLiteral("location(" + containerId + ",_,_)"));
                    removePerceptsByUnif(robotName, Literal.parseLiteral(
                            "container_relocated(\"" + containerId + "\",_,_)"));
                    addPercept(robotName, Literal.parseLiteral(
                            "container_relocated(\"" + containerId + "\","
                                    + container.getX() + "," + container.getY() + ")"));
                }
            }
            return true;
        } else if (error == 1) {
            addError(agName, "invalid_relocate", "Container not found: " + containerId);
        } else if (error == 2) {
            addError(agName, "already_picked", "Container already picked or not in PACKAGE: " + containerId);
        } else if (error == 3) {
            addError(agName, "dest_occupied", "Destination cell is not a free classification cell");
        } else if (error == 4) {
            addError(agName, "dest_out_of_bounds", "Destination is outside classification zone");
        } else {
            addError(agName, "unknown", "Unexpected error relocating container " + containerId);
        }
        return false;
    }

    /**
     * Acción: drop_at(ShelfId) Deposita el contenedor que lleva el robot en una
     * estantería adyacente.
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
     * Acción: assignTask(ContainerId, ShelfId) Asigna una tarea de transporte
     * al robot.
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
     * Acción: get_container_info(ContainerId) Añade una percepción con el peso,
     * dimensiones y tipo del contenedor.
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
     * Acción: get_location(ItemId) Añade una percepción location(ItemId, X, Y).
     */
    private boolean executeGetLocation(String agName, Structure action) {
        String itemId = action.getTerm(0).toString().replace("\"", "");
        // Descartar beliefs previos para este item (evita location/3 obsoletos
        // si el contenedor fue reubicado).
        removePerceptsByUnif(agName,
                Literal.parseLiteral("location(" + itemId + ",_,_)"));
        Literal locationInfo ;
        if(itemId.startsWith("shelf")){
            removePerceptsByUnif(agName,
                    Literal.parseLiteral("locationF(" + itemId + ",_,_)"));
            locationInfo = model.getFinalShelf(itemId);
             if (locationInfo != null) {
                 addPercept(agName, locationInfo);
             }
        }
        locationInfo = model.getLocation(itemId);

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
     * Acción: get_shelf_status(ShelfId) Añade una percepción
     * shelf_info(ShelfId, MaxW, CurW, MaxV, CurV).
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
     * Acción: task_complete(ContainerId, ShelfId) Marca la tarea como
     * completada y notifica al scheduler.
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

    /**
     * Acción: get_shelf_adjacent(ShelfId)
     * Añade percepción shelf_adjacent(ShelfId, [pos(X1,Y1), pos(X2,Y2), ...])
     * con las casillas accesibles (no-shelf) adyacentes al shelf.
     */
    private boolean executeGetShelfAdjacent(String agName, Structure action) {
        String shelfId = action.getTerm(0).toString().replace("\"", "");
        Literal adjacentInfo = model.getShelfAdjacentCells(shelfId);
        if (adjacentInfo != null) {
            removePerceptsByUnif(agName, Literal.parseLiteral("shelf_adjacent(" + shelfId + ",_)"));
            addPercept(agName, adjacentInfo);
            return true;
        }
        addError(agName, "shelf_not_found", "Shelf not found: " + shelfId);
        return false;
    }

    // -------------------------------------------------------------------------
    // UTILIDADES
    // -------------------------------------------------------------------------
    /**
     * Actualiza la percepción de posición de un robot concreto. Formato:
     * at(RobotId, X, Y)
     */
    private void updatePercepts(String agName) {
        Robot robot = model.getRobots().get(agName);
        if (robot == null) {
            return;
        }

        removePerceptsByUnif(agName, Literal.parseLiteral("at(_,_,_)"));
        addPercept(agName, Literal.parseLiteral(
                "at(\"" + robot.getId() + "\"," + robot.getX() + "," + robot.getY() + ")"
        ));
    }

    /**
     * Añade o elimina el percept occupied(X,Y) en el scheduler según el estado
     * de la celda. El scheduler lo usa como muros para el BFS de accesibilidad.
     */
    private void updateOccupancy(int x, int y, boolean occupied) {
        if (x < 0 || y < 0) {
            return;
        }
        Literal lit = Literal.parseLiteral("occupied(" + x + "," + y + ")");
        if (occupied) {
            addPercept("scheduler", lit);
        } else {
            removePercept("scheduler", lit);
        }
    }

    /**
     * Actualiza el percept container_at(CId, X, Y) en el scheduler para el
     * contenedor dado (reemplaza la posición previa).
     */
    private void updateContainerAt(String containerId, int x, int y) {
        removePerceptsByUnif("scheduler",
                Literal.parseLiteral("container_at(\"" + containerId + "\",_,_)"));
        addPercept("scheduler", Literal.parseLiteral(
                "container_at(\"" + containerId + "\"," + x + "," + y + ")"));
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
