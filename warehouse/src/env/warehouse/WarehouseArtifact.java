package warehouse;

import jason.asSyntax.*;
import jason.environment.Environment;
//import jason.environment.grid.Location;
import utils.Nodo;
import utils.Location;

import java.util.*;
import java.util.concurrent.*;
import java.util.stream.Collectors;

/**
 * Artefacto del almacén automatizado Proporciona la API para que los agentes
 * interactúen con el entorno
 */
public class WarehouseArtifact extends Environment {

    // Dimensiones del almacén
    private static final int GRID_WIDTH = 20;
    private static final int GRID_HEIGHT = 15;

    // Estructuras de datos del almacén
    private CellType[][] grid;
    private Map<String, Robot> robots;
    private Map<String, Container> containers;
    private Map<String, Shelf> shelves;
    private ConcurrentLinkedQueue<Container> pendingContainers;
    private Map<String, String> taskAssignments; // containerId -> robotId

    // GUI visual
    private WarehouseView view;

    // Contadores para generar IDs
    private int containerCounter = 0;

    // Métricas
    private int totalContainersProcessed = 0;
    private int totalErrors = 0;
    private long startTime;

    // Gestión del thread generador de contenedores
    private ExecutorService containerGeneratorExecutor;
    private volatile boolean running = true;

    @Override
    public void init(String[] args) {
        super.init(args);

        // Inicializar estructuras
        grid = new CellType[GRID_WIDTH][GRID_HEIGHT];
        robots = new ConcurrentHashMap<>();
        containers = new ConcurrentHashMap<>();
        shelves = new ConcurrentHashMap<>();
        pendingContainers = new ConcurrentLinkedQueue<>();
        taskAssignments = new ConcurrentHashMap<>();

        // Inicializar grid
        initializeGrid();

        // Crear robots
        initializeRobots();

        // Crear estanterías
        initializeShelves();

        // Crear GUI
        view = new WarehouseView(this, GRID_WIDTH, GRID_HEIGHT);
        view.setVisible(true);

        // Mensaje de bienvenida en la consola
        view.logMessage("========================================");
        view.logMessage(" Warehouse Management System Initialized");
        view.logMessage("   Grid: " + GRID_WIDTH + "x" + GRID_HEIGHT);
        view.logMessage("   Robots: " + robots.size());
        view.logMessage("   Shelves: " + shelves.size());
        view.logMessage("========================================");
        view.logMessage("");

        // Iniciar generador de contenedores
        startContainerGenerator();

        // Agregar shutdown hook para limpieza apropiada
        Runtime.getRuntime().addShutdownHook(new Thread(this::stop));

        startTime = System.currentTimeMillis();

        System.out.println("Warehouse environment initialized");
        System.out.println("Grid size: " + GRID_WIDTH + "x" + GRID_HEIGHT);
        System.out.println("Robots: " + robots.size());
        System.out.println("Shelves: " + shelves.size());
    }

    /**
     * Inicializa el grid con zonas
     */
    private void initializeGrid() {
        // Inicializar todos como vacíos
        for (int x = 0; x < GRID_WIDTH; x++) {
            for (int y = 0; y < GRID_HEIGHT; y++) {
                grid[x][y] = CellType.EMPTY;
            }
        }

        // Zona de entrada (arriba izquierda)
        for (int x = 0; x < 3; x++) {
            for (int y = 0; y < 2; y++) {
                grid[x][y] = CellType.ENTRANCE;
            }
        }

        // Zona de clasificación
        for (int x = 3; x < 7; x++) {
            for (int y = 0; y < 2; y++) {
                grid[x][y] = CellType.CLASSIFICATION;
            }
        }
    }

    /**
     * Crea los robots iniciales
     */
    private void initializeRobots() {
        Robot light = new Robot("robot_light", "light", 10, 1, 1, 3);
        light.setPosition(1, 3);
        robots.put("robot_light", light);

        Robot medium = new Robot("robot_medium", "medium", 30, 1, 2, 2);
        medium.setPosition(2, 3);
        robots.put("robot_medium", medium);

        Robot heavy = new Robot("robot_heavy", "heavy", 100, 2, 3, 1);
        heavy.setPosition(3, 3);
        robots.put("robot_heavy", heavy);
    }

    /**
     * Crea las estanterías del almacén
     */
    private void initializeShelves() {
        // Crear estanterías en el área de almacenamiento
        int shelfId = 1;

        // Fila de estanterías pequeñas
        for (int x = 10; x < 18; x += 2) {
            Shelf shelf = new Shelf("shelf_" + shelfId++, x, 2, 2, 2, 50, 8);
            shelves.put(shelf.getId(), shelf);
            grid[x][2] = CellType.SHELF;
            grid[x + 1][2] = CellType.SHELF;
            grid[x][3] = CellType.SHELF;
            grid[x + 1][3] = CellType.SHELF;
        }

        // Fila de estanterías medianas
        for (int x = 10; x < 18; x += 3) {
            Shelf shelf = new Shelf("shelf_" + shelfId++, x, 6, 3, 2, 100, 12);
            shelves.put(shelf.getId(), shelf);
            for (int dx = 0; dx < 3; dx++) {
                grid[x + dx][6] = CellType.SHELF;
                grid[x + dx][7] = CellType.SHELF;
            }
        }

        // Fila de estanterías grandes
        for (int x = 10; x < 16; x += 4) {
            Shelf shelf = new Shelf("shelf_" + shelfId++, x, 10, 4, 3, 200, 20);
            shelves.put(shelf.getId(), shelf);
            for (int dx = 0; dx < 4; dx++) {
                for (int dy = 0; dy < 3; dy++) {
                    grid[x + dx][10 + dy] = CellType.SHELF;
                }
            }
        }
    }

    /**
     * Inicia el generador automático de contenedores
     */
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
                    Container container = generateRandomContainer();
                    containers.put(container.getId(), container);
                    pendingContainers.offer(container);

                    System.out.println("New container generated: " + container);

                    // Log a la consola de la GUI
                    if (view != null) {
                        view.logMessage(String.format("New container: %s (%.1fkg, %s)",
                                container.getId(), container.getWeight(), container.getType()));
                    }
                    /**
                     * *********************************************************************************************************
                     */
                    // Notificar a los agentes
                    addPercept(Literal.parseLiteral("new_container(\"" + container.getId() + "\")"));
                    /**
                     * *********************************************************************************************************
                     */
                    if (view != null) {
                        view.update();
                    }

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

    /**
     * Detiene el entorno de forma limpia
     */
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

    /**
     * Genera un contenedor aleatorio
     */
    private Container generateRandomContainer() {
        Random rand = new Random();
        String id = "container_" + (++containerCounter);

        // Tamaños posibles: 1x1, 1x2, 2x2, 2x3
        int[][] sizes = {{1, 1}/*, {1,2}, {2,2}, {2,3}*/};
        int[] size = sizes[rand.nextInt(sizes.length)];

        // Peso aleatorio
        double weight = 5;//+ rand.nextDouble() * 95; // 5 a 100 kg

        // Tipo: standard (70%), fragile (15%), urgent (15%)
        String type;
        double r = rand.nextDouble();
        if (r < 0.70) {
            type = "standard";
        } else if (r < 0.85) {
            type = "fragile";
        } else {
            type = "urgent";
        }

        Container container = new Container(id, size[0], size[1], weight, type);
        container.setPosition(1, 1); // Posición inicial en zona de entrada

        return container;
    }

    //ESTO ES IMPORTANTE AQIO SE DEFINEN LAS ACCIONES QUE LOS AGENTES HACEN CON EL ENTORNO
    @Override
    public boolean executeAction(String agName, Structure action) {
        try {
            String actionName = action.getFunctor();

            switch (actionName) {
                case "move_to":
                    return executeMoveTo(agName, action);
                case "pickup":
                    return executePickup(agName, action);
                case "drop_at":
                    return executeDropAt(agName, action);
                case "request_task":
                    return executeRequestTask(agName, action);
                case "get_container_info":
                    return executeGetContainerInfo(agName, action);
                case "get_free_shelf":
                    return executeGetFreeShelf(agName, action);
                case "scan_surroundings":
                    return executeScanSurroundings(agName, action);
                case "getShelfUbication":
                    return executeGetShelfUbication(agName, action);
                case "taskcomplete":
                    return executeTaskComplete(agName, action);
                case "say":
                    executeSay(agName, action);
                    return true;
                default:
                    System.err.println("Unknown action: " + actionName);
                    return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private boolean executeSay(String agName, Structure action) {
        String message = action.getTerm(0).toString().replace("\"", "");
        if (view != null) {
            view.logMessage(agName + ": " + message);
            view.update();
        }
        return true;
    }

    private boolean executeTaskComplete(String agName, Structure action) {

        String containerId = action.getTerm(0).toString().replace("\"", "");
        String shelfId = action.getTerm(1).toString().replace("\"", "");

        Robot robot = robots.get(agName);
        Container container = containers.get(containerId);
        Shelf shelf = shelves.get(shelfId);

        if (robot == null || container == null || shelf == null) {
            return false;
        }

        // Marcar tarea como completada
        robot.setBusy(false);
        taskAssignments.remove(containerId, agName);
        removePercept(agName, Literal.parseLiteral("task(\"" + containerId + "\",\"" + shelfId + "\")"));
        // Log a la consola de la GUI
        if (view != null) {
            view.logMessage(String.format("%s completed task for %s at %s", agName, containerId, shelfId));
            view.update();
        }
        return true;
    }

    private boolean executeGetShelfUbication(String agName, Structure action) {

        String shelfId = action.getTerm(0).toString().replace("\"", "");
        Shelf shelf = shelves.get(shelfId);

        if (shelf == null) {
            return false;
        }

        // Agregar percepción con información de la estantería
        addPercept(agName, Literal.parseLiteral(
                "shelf_location(\"" + shelfId + "\","
                + shelf.getX() + ","
                + shelf.getY() + ")"
        ));

        return true;

    }

    /**
     * Acción: move_to(X, Y) Mueve el robot a la posición especificada
     */
    private boolean executeMoveTo(String agName, Structure action) {
        try {
            view.logMessage(String.format("%s moving to %s", agName, action.getTerm(0).toString()));
            view.update();

            Robot robot = robots.get(agName);
            String destination = action.getTerm(0).toString();
            //gestionarPercepcion(agName,  destination);
            removePerceptsByUnif(agName, Literal.parseLiteral("at(_)"));
            Location destLoc = getLocation(destination);
            Location currentLoc = new Location(robots.get(agName).getX(), robots.get(agName).getY());

            if (destLoc == null) {
                view.logMessage(String.format("invalid_destination: %s", destination));
                addError(agName, "invalid_destination", "Unknown destination: " + destination);
                return false;
            }
            if (currentLoc.equals(destLoc)) {
                addPercept(agName, Literal.parseLiteral("at(" + destination + ")"));
                view.update();
                return true; //ya estamos en el destino
            }
            Location nextStep = findNextStep(agName, destLoc, currentLoc);

            if (nextStep == null) {
                view.logMessage(String.format("no path to: %s", destination));
                addError(agName, "no_path", "No path to destination: " + destination);
                view.update();
                return false;
            }
            if (hayAgenteEn(nextStep)) { //gestionar Colision en dependencia de las prioridades del robot
                // replanificación automática
                Location alt = findNextStep(agName, destLoc, currentLoc);
                if (alt == null || hayAgenteEn(alt)) {
                    addError(agName, "blocked_by_agent", "Path blocked by another agent");
                    return false;
                }
                nextStep = alt;
            }
            robot.setPosition(nextStep.getX(), nextStep.getY());
            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: pickup(ContainerId) Recoge un contenedor
     */
    private boolean executePickup(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");

            Robot robot = robots.get(agName);
            Container container = containers.get(containerId);

            if (robot == null || container == null) {
                addError(agName, "invalid_pickup", "Robot or container not found");
                return false;
            }

            // Verificar distancia
            if (robot.distanceTo(container.getX(), container.getY()) > 1) {
                addError(agName, "too_far", "Container too far away");
                return false;
            }

            // Verificar capacidad
            if (!robot.canCarry(container)) {
                if (container.getWeight() > robot.getMaxWeight()) {
                    addError(agName, "container_too_heavy",
                            "Container " + containerId + " is too heavy for " + agName);
                } else {
                    addError(agName, "container_too_big",
                            "Container " + containerId + " is too big for " + agName);
                }
                return false;
            }

            // Recoger contenedor
            if (robot.pickup(container)) {
                container.setPicked(true);
                addPercept(agName, Literal.parseLiteral("picked(\"" + containerId + "\")"));

                if (view != null) {
                    view.logMessage(String.format("📦 %s picked up %s (%.1fkg)", agName, containerId, container.getWeight()));
                    view.update();
                }

                return true;
            }

            return false;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: drop_at(ShelfId) Deposita el contenedor en una estantería
     */
    private boolean executeDropAt(String agName, Structure action) {
        try {
            String shelfId = action.getTerm(0).toString().replace("\"", "");

            Robot robot = robots.get(agName);
            Shelf shelf = shelves.get(shelfId);

            if (robot == null || shelf == null) {
                addError(agName, "invalid_drop", "Robot or shelf not found");
                return false;
            }

            if (!robot.isCarrying()) {
                addError(agName, "not_carrying", "Robot is not carrying anything");
                return false;
            }
//**************************************************************************************************** */
            // Verificar distancia a la estantería esto no funciona
            if (robot.distanceTo(shelf.getX(), shelf.getY()) > 2) {
                addError(agName, "too_far", "Shelf too far away");
                return false;
            }
//**************************************************************************************************** */
            Container container = robot.getCarriedContainer();

            // Verificar si cabe en la estantería
            if (!shelf.canStore(container)) {
                addError(agName, "shelf_full", "Shelf " + shelfId + " cannot store container");
                return false;
            }

            // Depositar
            shelf.store(container);
            robot.drop();
            container.setAssignedShelf(shelfId);

            totalContainersProcessed++;

            // Actualizar percepciones
            removePerceptsByUnif(agName, Literal.parseLiteral("picked(_)"));
            addPercept(agName, Literal.parseLiteral("stored(\"" + container.getId() + "\",\"" + shelfId + "\")"));

            if (view != null) {
                view.logMessage(String.format("✅ %s stored %s at %s", agName, container.getId(), shelfId));
                view.update();
            }

            System.out.println(agName + " stored " + container.getId() + " at " + shelfId);

            if (view != null) {
                view.update();
            }

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: request_task() Solicita una nueva tarea del scheduler
     */
    private boolean executeRequestTask(String agName, Structure action) {
        try {
            Robot robot = robots.get(agName);
            if (robot == null) {
                return false;
            }

            // Si ya está ocupado, no asignar nueva tarea
            if (robot.isBusy() || robot.isCarrying()) {
                return true;
            }

            // Buscar contenedor pendiente
            Container container = pendingContainers.poll();
            if (container == null) {
                return true; // No hay tareas pendientes
            }

            // Verificar si el robot puede manejar el contenedor
            if (!robot.canCarry(container)) {
                // Devolver a la cola
                pendingContainers.offer(container);
                return true;
            }

            // Buscar estantería apropiada
            Shelf bestShelf = findBestShelf(container);
            if (bestShelf == null) {
                // No hay estanterías disponibles, devolver a la cola
                pendingContainers.offer(container);
                addError(agName, "no_shelf_available", "No shelf available for container");
                return true;
            }

            // Asignar tarea
            taskAssignments.put(container.getId(), agName);
            robot.setBusy(true);
            robot.setCurrentTask(container.getId());

            // Notificar al agente
            addPercept(agName, Literal.parseLiteral(
                    "task(\"" + container.getId() + "\",\"" + bestShelf.getId() + "\")"
            ));

            System.out.println("Task assigned to " + agName + ": " + container.getId() + " -> " + bestShelf.getId());

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Encuentra la mejor estantería para un contenedor
     */
    private Shelf findBestShelf(Container container) {
        List<Shelf> availableShelves = shelves.values().stream()
                .filter(s -> s.canStore(container))
                .sorted(Comparator.comparingDouble(Shelf::getOccupancyPercentage))
                .collect(Collectors.toList());

        return availableShelves.isEmpty() ? null : availableShelves.get(0);
    }

    /**
     * Acción: get_container_info(ContainerId) Obtiene información sobre un
     * contenedor
     */
    private boolean executeGetContainerInfo(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            Container container = containers.get(containerId);

            if (container == null) {
                return false;
            }

            // Agregar percepción con información del contenedor
            addPercept(agName, Literal.parseLiteral(
                    "container_info(\"" + containerId + "\","
                    + container.getWidth() + ","
                    + container.getHeight() + ","
                    + container.getWeight() + ",\""
                    + container.getType() + "\")"
            ));

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: get_free_shelf(ContainerId) Busca una estantería libre para un
     * contenedor
     */
    private boolean executeGetFreeShelf(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            Container container = containers.get(containerId);

            if (container == null) {
                return false;
            }

            Shelf shelf = findBestShelf(container);
            if (shelf != null) {
                addPercept(agName, Literal.parseLiteral(
                        "free_shelf(\"" + containerId + "\",\"" + shelf.getId() + "\")"
                ));
                return true;
            }

            return false;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: scan_surroundings() Escanea las celdas alrededor del robot
     */
    private boolean executeScanSurroundings(String agName, Structure action) {
        try {
            Robot robot = robots.get(agName);
            if (robot == null) {
                return false;
            }

            int x = robot.getX();
            int y = robot.getY();

            // Escanear celdas adyacentes
            for (int dx = -2; dx <= 2; dx++) {
                for (int dy = -2; dy <= 2; dy++) {
                    int nx = x + dx;
                    int ny = y + dy;

                    if (nx >= 0 && nx < GRID_WIDTH && ny >= 0 && ny < GRID_HEIGHT) {
                        CellType type = grid[nx][ny];
                        addPercept(agName, Literal.parseLiteral(
                                "cell(" + nx + "," + ny + "," + type.name().toLowerCase() + ")"
                        ));

                        if (type == CellType.BLOCKED) {
                            addPercept(agName, Literal.parseLiteral("blocked(" + nx + "," + ny + ")"));
                        }
                    }
                }
            }

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

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

    // Getters para la vista
    public CellType[][] getGrid() {
        return grid;
    }

    public Map<String, Robot> getRobots() {
        return robots;
    }

    public Map<String, Container> getContainers() {
        return containers;
    }

    public Map<String, Shelf> getShelves() {
        return shelves;
    }

    public int getPendingContainersCount() {
        return pendingContainers.size();
    }

    public int getTotalContainersProcessed() {
        return totalContainersProcessed;
    }

    public int getTotalErrors() {
        return totalErrors;
    }

    public String getStatistics() {
        long elapsedTime = (System.currentTimeMillis() - startTime) / 1000;
        return String.format(
                "Time: %ds | Processed: %d | Pending: %d | Errors: %d",
                elapsedTime, totalContainersProcessed, pendingContainers.size(), totalErrors
        );
    }

    private Location getLocation(String location) {
        switch (location) {
            case "shelf1":
                return new Location(shelves.get("shelf_1").getX(), shelves.get("shelf_1").getY());
            case "shelf2":
                return new Location(shelves.get("shelf_2").getX(), shelves.get("shelf_2").getY());
            case "shelf3":
                return new Location(shelves.get("shelf_3").getX(), shelves.get("shelf_3").getY());
            case "shelf4":
                return new Location(shelves.get("shelf_4").getX(), shelves.get("shelf_4").getY());
            case "shelf5":
                return new Location(shelves.get("shelf_5").getX(), shelves.get("shelf_5").getY());
            case "shelf6":
                return new Location(shelves.get("shelf_6").getX(), shelves.get("shelf_6").getY());
            case "shelf7":
                return new Location(shelves.get("shelf_7").getX(), shelves.get("shelf_7").getY());
            case "shelf8":
                return new Location(shelves.get("shelf_8").getX(), shelves.get("shelf_8").getY());
            case "shelf9":
                return new Location(shelves.get("shelf_9").getX(), shelves.get("shelf_9").getY());
            case "entrance":
                return new Location(1, 1);
            case "lightInit":
                return new Location(9, 3);
            case "mediumInit":
                return new Location(4, 3);
            case "heavyInit":
                return new Location(5, 3);
            default:
                return null;
        }
    }
// quedarnos solo con el siguiente paso en vez de toda la ruta, gestionar colisiones y prioridades de los robots

    private Location findNextStep(String agName, Location dest, Location current) {

        List<Nodo> camino = this.A_star(agName, current, dest);

        if (camino == null || camino.size() < 2) {
            view.logMessage(String.format("no se encontro camino de %s a %s", current, dest));
            view.update();
            return null;
        }

        return camino.get(1).getLoc();
    }

    public List<Nodo> A_star(String agName, Location start, Location dest) {

        PriorityQueue<Nodo> opened = new PriorityQueue<>();
        Map<Location, Integer> mejorG = new HashMap<>();
        Set<Location> closed = new HashSet<>();

        Nodo inicial = new Nodo(start, null, 0, start.distance(dest));
        opened.add(inicial);
        mejorG.put(start, 0);

        int[][] dirs = {{1, 0}, {0, 1}, {-1, 0}, {0, -1}};

        while (!opened.isEmpty()) {

            Nodo actual = opened.poll();

            if (actual.getLoc().equals(dest)) {
                List<Nodo> camino = new ArrayList<>();
                while (actual != null) {
                    camino.add(actual);
                    actual = actual.getPadre();
                }
                Collections.reverse(camino);
                return camino;
            }

            if (closed.contains(actual.getLoc())) {
                continue;
            }
            closed.add(actual.getLoc());

            for (int[] d : dirs) {

                int nx = actual.getLoc().getX() + d[0];
                int ny = actual.getLoc().getY() + d[1];

                if (!canMoveTo(agName, nx, ny)) {
                    continue;
                }

                Location nueva = new Location(nx, ny);

                int nuevoG = actual.getG() + 1 + penaltyRobotsNearby(agName, nx, ny);

                if (mejorG.containsKey(nueva) && mejorG.get(nueva) <= nuevoG) {
                    continue;
                }

                mejorG.put(nueva, nuevoG);

                opened.add(new Nodo(
                        nueva,
                        actual,
                        nuevoG,
                        nueva.distance(dest)
                ));
            }
        }
        view.logMessage(String.format("%s no pudo encontrar camino a %s", agName, dest));
        view.update();
        return null;
    }

    
    private boolean canMoveTo(String agName, int x, int y) {
        // Limites del grid
        if (x < 0 || x >= GRID_WIDTH || y < 0 || y >= GRID_HEIGHT) {
            return false;
        }

        CellType cell = grid[x][y];
        if (cell == CellType.BLOCKED /*|| cell == CellType.SHELF*/) {
            return false;
        }

        return true; // Permitimos celdas ocupadas
    }

    private int penaltyRobotsNearby(String agName, int x, int y) {
        Robot self = robots.get(agName);
        if (self == null) {
            return 0;
        }

        int penalty = 0;

        for (Robot r : robots.values()) {
            if (!r.getId().equals(agName)) {
                int dist = r.distanceTo(x, y);

                if (dist == 0) {
                    // Celda ocupada actualmente: penalización alta
                    penalty += 50; // ajustable
                } else if (dist == 1) {
                    if (r.getSpeed() >= self.getSpeed()) {
                        penalty += 6;
                    } else {
                        penalty += 2;
                    }
                }
            }
        }
        return penalty;
    }

    boolean hayAgenteEn(Location loc) {
        for (Robot r : robots.values()) {
            if (r.getX() == loc.getX() && r.getY() == loc.getY()) {
                return true;
            }
        }
        return false;
    }
}
