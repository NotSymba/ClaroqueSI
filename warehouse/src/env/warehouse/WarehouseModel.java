package warehouse;

import jason.asSyntax.*;
import jason.environment.Environment;
import jason.environment.grid.GridWorldModel;

import utils.Nodo;
import warehouse.Robot;
import warehouse.WarehouseView;
import utils.Location;

import java.util.*;
import java.util.concurrent.*;
import java.util.stream.Collectors;

import javax.swing.Action;

public class WarehouseModel extends GridWorldModel {

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
    // Contadores para generar IDs
    private int containerCounter = 0;

    // Métricas
    private int totalContainersProcessed = 0;
    private int totalErrors = 0;
    private long startTime;

    // Gestión del thread generador de contenedores
    private ExecutorService containerGeneratorExecutor;
    private volatile boolean running = true;

    public WarehouseModel() {
        super(GRID_WIDTH, GRID_HEIGHT, 3);

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
    public Container newContainer() {
        Container container = generateRandomContainerFair();
        containers.put(container.getId(), container);
        pendingContainers.offer(container);

        System.out.println("New container generated: " + container);

        // Log a la consola de la GUI
        return container;

    }

    /**
     * Detiene el entorno de forma limpia
     */
    /**
     * Genera un contenedor aleatorio
     */
    public boolean taskComplete(String agName, Structure action) {

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

        // Log a la consola de la GUI
        return true;
    }

    public int moveTo(String agName, Structure action) {
        try {

            Robot robot = robots.get(agName);
            String destination = action.getTerm(0).toString();

            Location destLoc = getLocation(destination);
            Location currentLoc = new Location(robots.get(agName).getX(), robots.get(agName).getY());

            if (currentLoc.equals(destLoc)) {
                return 0; // Ya está en el destino
            }
            if (destLoc == null) {
                return 1;
            }

            Location nextStep = findNextStep(agName, destLoc, currentLoc);

            if (nextStep == null) {
                return 2;
            }
            if (hayAgenteEn(nextStep)) { //gestionar Colision en dependencia de las prioridades del robot
                // replanificación automática
                Location alt = findNextStep(agName, destLoc, currentLoc);
                if (alt == null || hayAgenteEn(alt)) {
                    return 3;
                }
                nextStep = alt;
            }
            robot.setPosition(nextStep.getX(), nextStep.getY());
            return 0;

        } catch (Exception e) {
            e.printStackTrace();
            return 4;
        }
    }

    public int dropContainer(String agName, Structure action) {
        try {
            String shelfId = action.getTerm(0).toString().replace("\"", "");

            Robot robot = robots.get(agName);
            Shelf shelf = shelves.get(shelfId);

            if (robot == null || shelf == null) {
                return 1;
            }

            if (!robot.isCarrying()) {
                return 2;
            }
//**************************************************************************************************** */
            // tapirico
            if (!isAdjacentToShelf(agName, shelfId)) {
                return 3;
            }
//**************************************************************************************************** */
            Container container = robot.getCarriedContainer();

            // Verificar si cabe en la estantería
            if (!shelf.canStore(container)) {
                return 4;
            }

            // Depositar
            shelf.store(container);
            robot.drop();
            container.setAssignedShelf(shelfId);

            totalContainersProcessed++;

            return 0;

        } catch (Exception e) {
            e.printStackTrace();
            return 5;
        }
    }

    public int pickUp(String agName, Structure action) {

        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");

            Robot robot = robots.get(agName);
            Container container = containers.get(containerId);

            if (robot == null || container == null) {
                //addError(agName, "invalid_pick", "Robot or container not found");
                return 1;
            }

            if (robot.isCarrying()) {
                //addError(agName, "already_carrying", "Robot is already carrying something");
                return 2;
            }

            // Verificar distancia a la zona de entrada
            if (robot.distanceTo(1, 1) > 2) {
                //addError(agName, "too_far", "Container too far away");
                return 3;
            }

            // Recoger
            robot.pickup(container);
            container.setPicked(true);

            return 0;

        } catch (Exception e) {
            e.printStackTrace();
            return 4;
        }
    }

    /* NO LO VAMOS A USAR
    private boolean scanSurroundings(String agName, Structure action) {
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
     */
    public Literal getFreeShelf(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            Container container = containers.get(containerId);

            if (container == null) {
                return null;
            }

            Shelf shelf = findBestShelf(container);
            if (shelf != null) {
                return Literal.parseLiteral(
                        "free_shelf(\"" + containerId + "\",\"" + shelf.getId() + "\")"
                );
            }

            return null;

        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public Literal getContainerInfo(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            Container container = containers.get(containerId);

            if (container == null) {
                return null;
            }

            // Agregar percepción con información del contenedor
            Literal toRet = Literal.parseLiteral(
                    "container_info(\"" + containerId + "\","
                    + container.getWidth() + ","
                    + container.getHeight() + ","
                    + container.getWeight() + ",\""
                    + container.getType() + "\")"
            );

            return toRet;

        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public String assignTask(String agName, Structure action) {
        try {
            Robot robot = robots.get(agName);
            if (robot == null) {
                return "null";
            }

            // Si ya está ocupado, no asignar nueva tarea
            if (robot.isBusy() || robot.isCarrying()) {
                return "busy";
            } // Robot ocupado o ya cargando algo

            // Buscar contenedor pendiente
            Container container = pendingContainers.poll();
            if (container == null) {
                return "no_task";
            } // No hay tareas pendientes

            // Verificar si el robot puede manejar el contenedor
            if (!robot.canCarry(container)) {
                // Devolver a la cola
                pendingContainers.offer(container);
                return "cannot_carry";
            }

            // Buscar estantería apropiada
            Shelf bestShelf = findBestShelf(container);
            if (bestShelf == null) {
                // No hay estanterías disponibles, devolver a la cola
                pendingContainers.offer(container);
                return "no_shelf_available";
            }

            // Asignar tarea
            taskAssignments.put(container.getId(), agName);
            robot.setBusy(true);
            robot.setCurrentTask(container.getId());

            // Notificar al agente
            System.out.println("Task assigned to " + agName + ": " + container.getId() + " -> " + bestShelf.getId());

            return Literal.parseLiteral(
                    "task(\"" + container.getId() + "\",\"" + bestShelf.getId() + "\")").toString();

        } catch (Exception e) {
            e.printStackTrace();
            return "error";
        }
    }
//--------------------------------------------------------------------------------------------------------------
//UTILIDADES

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

    //funcion auxiliar para obtener una clase ubicacion a partir de un string
    public Location getLocation(String location) {
        switch (location) {
            case "shelf_1":
                return findShelfMiddlePoint(shelves.get("shelf_1"));
            case "shelf_2":
                return findShelfMiddlePoint(shelves.get("shelf_2"));
            case "shelf_3":
                return findShelfMiddlePoint(shelves.get("shelf_3"));
            case "shelf_4":
                return findShelfMiddlePoint(shelves.get("shelf_4"));
            case "shelf_5":
                return findShelfMiddlePoint(shelves.get("shelf_5"));
            case "shelf_6":
                return findShelfMiddlePoint(shelves.get("shelf_6"));
            case "shelf_7":
                return findShelfMiddlePoint(shelves.get("shelf_7"));
            case "shelf_8":
                return findShelfMiddlePoint(shelves.get("shelf_8"));
            case "shelf_9":
                return findShelfMiddlePoint(shelves.get("shelf_9"));
            case "entrance":
                return new Location(1, 1);
            case "lightInit":
                return new Location(0, 5);
            case "mediumInit":
                return new Location(1, 5);
            case "heavyInit":
                return new Location(2, 5);
            default:
                return null;
        }
    }
//para el move

    private Location findNextStep(String agName, Location dest, Location current) {

        Location realDest = dest;

        if (!canMoveTo(agName, dest.getX(), dest.getY())) {
            realDest = getNearestFreeCell(dest);
        }

        if (realDest == null) {
            return null;
        }

        List<Nodo> camino = this.A_star(agName, current, realDest);

        if (camino == null || camino.size() < 2) {
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

        return null;
    }

    private boolean canMoveTo(String agName, int x, int y) {
        // Limites del grid
        if (x < 0 || x >= GRID_WIDTH || y < 0 || y >= GRID_HEIGHT) {
            return false;
        }

        CellType cell = grid[x][y];
        if (cell == CellType.BLOCKED || cell == CellType.SHELF) {
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

    public String getStatistics() {
        long elapsedTime = (System.currentTimeMillis() - startTime) / 1000;
        return String.format(
                "Time: %ds | Processed: %d | Pending: %d | Errors: %d",
                elapsedTime, totalContainersProcessed, pendingContainers.size(), totalErrors
        );
    }

    //----------------------------------------------------------------------------------------
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

    private Location findShelfMiddlePoint(Shelf shelf) {
        int midX = shelf.getX() + shelf.getWidth() / 2;
        int midY = shelf.getY() + shelf.getHeight() / 2;
        return new Location(midX, midY);
    }

    //la casilla libre mas cercana a la estantería, para que el robot se acerque lo máximo posible aunque no pueda llegar a la casilla central  
    private Location getNearestFreeCell(Location dest) {

        if (canMoveTo("", dest.getX(), dest.getY())) {
            return dest;
        }

        Queue<Location> queue = new LinkedList<>();
        Set<Location> visited = new HashSet<>();

        queue.add(dest);
        visited.add(dest);

        int[][] dirs = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};

        while (!queue.isEmpty()) {

            Location current = queue.poll();

            for (int[] d : dirs) {

                int nx = current.getX() + d[0];
                int ny = current.getY() + d[1];

                Location next = new Location(nx, ny);

                if (visited.contains(next)) {
                    continue;
                }

                visited.add(next);

                if (nx < 0 || nx >= GRID_WIDTH || ny < 0 || ny >= GRID_HEIGHT) {
                    continue;
                }

                if (canMoveTo("", nx, ny)) {
                    return next;
                }

                queue.add(next);
            }
        }

        return null;
    }
    //funcion auxiliar llamada desde el artifact para saber si el robot es adyacente a una estateria

    public boolean isAdjacentToShelf(String robotID, String shelfID) {
        Robot robot = robots.get(robotID);
        Shelf shelf = shelves.get(shelfID);
        int rx = robot.getX();
        int ry = robot.getY();

        int sx = shelf.getX();
        int sy = shelf.getY();
        int sw = shelf.getWidth();
        int sh = shelf.getHeight();

        int minX = sx;
        int maxX = sx + sw - 1;
        int minY = sy;
        int maxY = sy + sh - 1;

        // izquierda
        if (rx == minX - 1 && ry >= minY && ry <= maxY) {
            return true;
        }

        // derecha
        if (rx == maxX + 1 && ry >= minY && ry <= maxY) {
            return true;
        }

        // arriba
        if (ry == minY - 1 && rx >= minX && rx <= maxX) {
            return true;
        }

        // abajo
        if (ry == maxY + 1 && rx >= minX && rx <= maxX) {
            return true;
        }

        return false;
    }

    //*******************************************************************************************************/
    //funciones de generacion de cajas aleatoria dada, se implementara una donde el trabajo se reparta de fornma justa
    private Container generateRandomContainerUnfair() {
        Random rand = new Random();
        String id = "container_" + (++containerCounter);

        // Tamaños posibles: 1x1, 1x2, 2x2, 2x3
        int[][] sizes = {{1, 1}, {1, 2}, {2, 2}, {2, 3}};
        int[] size = sizes[rand.nextInt(sizes.length)];

        // Peso aleatorio
        double weight = 5 + rand.nextDouble() * 95; // 5 a 100 kg

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

    //solo genera cajas pequeñas y ligeras para probar el sistema con el robot light, se puede cambiar a la función anterior para generar cajas de forma más variada
    private Container generateLightContainer() {
        Random rand = new Random();
        String id = "container_" + (++containerCounter);

        // Tamaños posibles: 1x1, 1x2, 2x2, 2x3
        int[][] sizes = {{1, 1}};
        int[] size = sizes[rand.nextInt(sizes.length)];

        // Peso aleatorio
        double weight = 5;// 5 a 100 kg

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
//solo genera cajas grandes y pesadas para probar el sistema con el robot heavy, se puede cambiar a la función anterior para generar cajas de forma más variada

    private Container generateMediumContainer() {
        Random rand = new Random();
        String id = "container_" + (++containerCounter);

        // Tamaños posibles: 1x1, 1x2, 2x2, 2x3
        int[][] sizes = {{1, 2}};
        int[] size = sizes[rand.nextInt(sizes.length)];

        // Peso aleatorio
        double weight = 28;// 5 a 100 kg

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

    //solo genera cajas grandes y pesadas para probar el sistema con el robot heavy, se puede cambiar a la función anterior para generar cajas de forma más variada
    private Container generateHeavyContainer() {
        Random rand = new Random();
        String id = "container_" + (++containerCounter);

        // Tamaños posibles: 1x1, 1x2, 2x2, 2x3
        int[][] sizes = {{2, 2}, {2, 3}};
        int[] size = sizes[rand.nextInt(sizes.length)];

        // Peso aleatorio
        double weight = 95;// 5 a 100 kg

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
//generacion justa de contenedores que hara que todos los robots tengan tareas acordes a sus capacidades, para probar el sistema con una carga de trabajo equilibrada, se puede cambiar a la función anterior para generar cajas de forma más variada y menos justa
    private Container generateRandomContainerFair() {

        Random rand = new Random();
        String id = "container_" + (++containerCounter);

        int width;
        int height;
        double weight;

        double category = rand.nextDouble();

        // 33% -> cajas pequeñas
        if (category < 0.33) {

            int[][] sizes = {{1, 1}};
            int[] size = sizes[rand.nextInt(sizes.length)];

            width = size[0];
            height = size[1];

            weight = 5 + rand.nextDouble() * 5; // <=10 kg
        } // 33% -> cajas medianas
        else if (category < 0.66) {

            int[][] sizes = {{1, 1}, {1, 2}};
            int[] size = sizes[rand.nextInt(sizes.length)];

            width = size[0];
            height = size[1];

            weight = 10 + rand.nextDouble() * 20; // <=30 kg
        } // 33% -> cajas grandes
        else {

            int[][] sizes = {{1, 1}, {1, 2}, {2, 2}, {2, 3}};
            int[] size = sizes[rand.nextInt(sizes.length)];

            width = size[0];
            height = size[1];

            weight = 30 + rand.nextDouble() * 70; // <=100 kg
        }

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

        Container container = new Container(id, width, height, weight, type);
        container.setPosition(1, 1);

        return container;
    }
}
