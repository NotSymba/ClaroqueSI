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
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

import javax.swing.Action;

public class WarehouseModel extends GridWorldModel {

    int proporcionMovAccion = 3;
    int speed = 75; // velocidad de los ticks, ajustable para acelerar o ralentizar la simulación
    // Dimensiones del almacén
    private static final int GRID_WIDTH = 20;
    private static final int GRID_HEIGHT = 15;

    // Estructuras de datos del almacén
    private CellType[][] grid;
    private Map<String, Robot> robots;
    private Map<String, Container> containers;
    private Map<String, Shelf> shelves;
    //presindire de eso
    private ConcurrentLinkedQueue<Container> pendingContainers;
    private Map<String, String> taskAssignments; // containerId -> robotId

    // Dentro de WarehouseModel
    private Map<Integer, Map<Location, String>> reservationTable; // tick -> (Location -> robotId)  
    // GUI visual
    // Contadores para generar IDs
    private int containerCounter = 0;
    // Métricas
    private int totalContainersProcessed = 0;
    private int totalErrors = 0;
    private long startTime;

    // Gestión del thread generador de contenedores
    private volatile int currentTick = 0;
    private ExecutorService tickCountExecutor;
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
        reservationTable = new ConcurrentHashMap<>();
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
        startTickExecutor();
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
        System.out.println("Shelves keys: " + shelves.keySet());
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
//contador de ticks de move

    private void startTickExecutor() {
        tickCountExecutor = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "tickCounterThread");
            t.setDaemon(true);
            return t;
        });

        tickCountExecutor.submit(() -> {
            try {
                while (running) {
                    // Avanzar tick global
                    currentTick++;

                    // Limpiar reservas > 10 ticks atrás
                    reservationTable.entrySet().removeIf(entry -> entry.getKey() < currentTick - 10);

                    Thread.sleep(speed); //

                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });

    }

    public void stopTickExecutor() {
        running = false;
        if (tickCountExecutor != null) {
            tickCountExecutor.shutdownNow();
        }
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
            totalErrors++;
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

            if (destLoc == null) {
                totalErrors++;
                return 1;
            }
            if (currentLoc.equals(destLoc)) {
                return 0; // Ya está en el destino
            }
            //quitar
            /*
            if (!destination.startsWith("shelf_") && !canMoveToWithReservation(robot, destLoc, curren)) { // si hay agente lo mejor es que espere 1 turno a que se libere la casilla
                totalErrors++;
                System.out.println("error de ruta destino ocupado");
                return 3; // Destino ocupado
            }
             */
            Location nextStep = findNextStep(agName, destLoc, currentLoc);
            // int moveTime = moveTime(robot);

            if (nextStep == null) {
                totalErrors++;
                System.out.println("error de ruta : no ruta");
                return 3;
            }
            //necesario porque tenemos desface temporal
            if (!canMoveToWithReservation(robot, nextStep, currentTick)) {
                totalErrors++;
                System.out.println("error de ruta: agente en ruta");
                return 3; // Destino ocupado
            }
            //agente estatico ocupando un lugar
            if (hayAgenteEn(nextStep)) {
                totalErrors++;
                System.out.println("error de ruta: agente estatico en ruta");
                return 3; // Destino ocupado
            }
            robot.setPosition(nextStep.getX(), nextStep.getY());

            return 0;

        } catch (Exception e) {
            e.printStackTrace();
            totalErrors++;
            return 4;
        }
    }

    public int dropContainer(String agName, Structure action) {
        try {
            String shelfId = action.getTerm(0).toString().replace("\"", "");

            Robot robot = robots.get(agName);
            Shelf shelf = shelves.get(shelfId);

            if (robot == null || shelf == null) {
                totalErrors++;
                return 1;
            }

            if (!robot.isCarrying()) {
                totalErrors++;
                return 2;
            }
//**************************************************************************************************** */
            // tapirico
            if (!isAdjacentToShelf(agName, shelfId)) {
                totalErrors++;
                return 3;
            }
//**************************************************************************************************** */

            Container container = robot.getCarriedContainer();
            System.out.println("Intentando depositar " + container.getId() + " en " + shelf.getId());
            // Verificar si cabe en la estantería
            if (!shelf.canStore(container)) {
                totalErrors++;
                return 4;
            }

            // Depositar
            shelf.store(container);
            robot.drop();
            reserveAction(robot, new Location(robot.getX(), robot.getY())); // Reservar la celda por el tiempo que permaneceremos
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
                totalErrors++;
                return 1;
            }

            if (robot.isCarrying()) {
                totalErrors++;
                return 2;
            }

            // Verificar distancia a la zona de entrada
            if (robot.distanceTo(1, 1) > 2) {
                totalErrors++;
                return 3;
            }

            // Recoger
            robot.pickup(container);
            container.setPicked(true);
            reserveAction(robot, new Location(robot.getX(), robot.getY())); // Reservar la celda por el tiempo que permaneceremos
            return 0;

        } catch (Exception e) {
            totalErrors++;
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
                totalErrors++;
                return null;
            }

            Shelf shelf = findBestShelf(container);
            if (shelf != null) {
                return Literal.parseLiteral(
                        "free_shelf(\"" + containerId + "\",\"" + shelf.getId() + "\")"
                );
            }
            //no hay estanterías disponibles, el agente debería esperar a que se libere alguna, pero por ahora solo le decimos que no hay estanterías disponibles y que lo intente de nuevo luego
            totalErrors++;
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
                totalErrors++;
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
            totalErrors++;
            e.printStackTrace();
            return null;
        }
    }

    public String assignTask(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            Container container = containers.get(containerId);

            Robot robot = robots.get(agName);
            // Verificar si el robot existe
            if (robot == null) {
                totalErrors++;
                return "null_robot";
            }
            //la tarea ya fue asignada a otro robot, no asignar nueva tarea
            if (taskAssignments.containsKey(containerId)) {
                totalErrors++;
                return "already_assigned";
            }

            // Si ya está ocupado, no asignar nueva tarea
            if (robot.isBusy() || robot.isCarrying()) {
                totalErrors++;
                return "busy";
            } // Robot ocupado o ya cargando algo

            // Verificar si el contenedor existe
            if (container == null) {
                totalErrors++;
                return "null_container";
            }

            // Verificar si el robot puede manejar el contenedor
            if (!robot.canCarry(container)) {
                totalErrors++;
                return "cannot_carry";
            }

            // Buscar estantería apropiada
            Shelf bestShelf = findBestShelf(container);
            if (bestShelf == null) {
                totalErrors++;
                // No hay estanterías disponibles, devolver a la cola
                return "no_shelf_available";
            }

            // Asignar tarea
            taskAssignments.put(container.getId(), agName);
            robot.setBusy(true);
            robot.setCurrentTask(container.getId());

            // Notificar al agente
            System.out.println("Task assigned to " + agName + ": " + container.getId() + " -> " + bestShelf.getId());
            pendingContainers.poll(); // Sacar el contenedor de la cola de pendientes

            return Literal.parseLiteral(
                    "task(" + container.getId() + "," + bestShelf.getId() + ")").toString();

        } catch (Exception e) {
            e.printStackTrace();
            totalErrors++;

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
        if (location.startsWith("shelf_")) {
            Shelf s = shelves.get(location);
            if (s != null) {
                return findShelfMiddlePoint(s);
            }
            return null;
        }

        switch (location) {
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

        if (!canMoveToWithReservation(robots.get(agName), dest, currentTick)) {
            realDest = getNearestFreeCell(robots.get(agName), dest);
        }

        if (realDest == null) {
            return null;
        }

        List<Nodo> camino = this.A_star(agName, current, realDest);

        if (camino == null || camino.size() < 2) {
            return null;
        }
        clearReservations(agName);
        reservePath(robots.get(agName), camino);
        return camino.get(1).getLoc();
    }

    public List<Nodo> A_star(String agName, Location start, Location dest) {
        int startTick = currentTick;
        PriorityQueue<Nodo> open = new PriorityQueue<>(Comparator.comparingInt(Nodo::getF));
        Map<Location, Integer> bestG = new HashMap<>();
        Set<String> closed = new HashSet<>();

        Nodo inicial = new Nodo(start, null, 0, start.distance(dest), startTick);
        open.add(inicial);
        bestG.put(start, 0);

        int[][] dirs = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {0, 0}}; // 0,0 -> esperar un tick

        while (!open.isEmpty()) {
            Nodo actual = open.poll();
            String key = actual.getLoc().getX() + "," + actual.getLoc().getY() + "," + actual.getTick();
            if (closed.contains(key)) {
                continue;
            }
            closed.add(key);

            if (actual.getLoc().equals(dest)) {
                // Reconstruir camino
                List<Nodo> path = new ArrayList<>();
                Nodo n = actual;
                while (n != null) {
                    path.add(n);
                    n = n.getPadre();
                }
                Collections.reverse(path);
                return path;
            }

            for (int[] d : dirs) {
                int nx = actual.getLoc().getX() + d[0];
                int ny = actual.getLoc().getY() + d[1];
                Location nextLoc = new Location(nx, ny);
                int moveTime = moveTime(robots.get(agName));

                // Tick en que ocuparíamos esta celda
                int nextTick = actual.getTick() + 1;

                // Verificar límites y obstáculos
                if (!canMoveToWithReservation(robots.get(agName), nextLoc, nextTick)) {
                    continue;
                }

                // Verificar reservas en ticks exactos
                boolean blocked = false;
                for (int t = 0; t < moveTime; t++) {
                    int checkTick = nextTick + t;
                    Map<Location, String> reserved = reservationTable.getOrDefault(checkTick, Collections.emptyMap());
                    String reserver = reserved.get(nextLoc);
                    if (reserver != null && !reserver.equals(agName)) {
                        blocked = true;
                        break;
                    }
                }
                if (blocked) {
                    continue;
                }

                int g = actual.getG() + moveTime + penaltyRobotsNearby(agName, nx, ny);
                if (bestG.containsKey(nextLoc) && bestG.get(nextLoc) <= g) {
                    continue;
                }
                bestG.put(nextLoc, g);

                open.add(new Nodo(nextLoc, actual, g, nextLoc.distance(dest), nextTick));
            }
        }

        return null; // no se encontró camino
    }

    private boolean canMoveTo(int x, int y) {
        // Limites del grid
        Robot test;

        if (x < 0 || x >= GRID_WIDTH || y < 0 || y >= GRID_HEIGHT) {
            return false;
        }

        CellType cell = grid[x][y];
        if (cell == CellType.BLOCKED || cell == CellType.SHELF) {
            return false;
        }
        Location loc = new Location(x, y);

        // Comprobar si la celda es alguna de las posiciones init y si hay un robot
        if (loc.equals(getLocation("lightInit")) && hayAgenteEn(loc)) {
            return false;
        }
        if (loc.equals(getLocation("mediumInit")) && hayAgenteEn(loc)) {
            return false;
        }
        if (loc.equals(getLocation("heavyInit")) && hayAgenteEn(loc)) {
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

    //encuentra el punto medio pero desplazado a la casilla de arriba a la izquierda para que sea 
    //mas probable que se encuentre casillas libres mas cercanas al robot
    private Location findShelfMiddlePoint(Shelf shelf) {
        int midX = shelf.getX() + shelf.getWidth() / 2 - 1;
        int midY = shelf.getY() + shelf.getHeight() / 2 - 1;
        return new Location(midX, midY);
    }

    //la casilla libre mas cercana a la estantería, para que el robot se acerque lo máximo posible aunque no pueda llegar a la casilla central  
    private Location getNearestFreeCell(Robot robot, Location dest) {
        //ya se comprueva
        /*
        if (canMoveToWithReservation(robot, dest)) {
            return dest;
        }
         */

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

                if (canMoveTo(nx, ny) && !hayAgenteEn(next)) {
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
//--------------------------------------------------------------------------------------------------------
//mas de pathfinding y movimiento
//CREO QUE ESTA BUGED

    private boolean canMoveToWithReservation(Robot robot, Location loc, int tick) {

        int moveTime = moveTime(robot);

        for (int t = 0; t < moveTime; t++) {

            int futureTick = tick + t;

            Map<Location, String> reserved
                    = reservationTable.getOrDefault(futureTick, Collections.emptyMap());

            String reserver = reserved.get(loc);

            if (reserver != null && !reserver.equals(robot.getId())) {
                return false;
            }
        }

        return canMoveTo(loc.getX(), loc.getY());
    }

    private void reservePath(Robot robot, List<Nodo> path) {
        for (Nodo n : path) {
            int moveTime = moveTime(robot);
            for (int t = 0; t < moveTime; t++) {
                int futureTick = n.getTick() + t;
                reservationTable
                        .computeIfAbsent(futureTick, k -> new ConcurrentHashMap<>())
                        .put(n.getLoc(), robot.getId());
            }
        }
    }

    private void clearReservations(String robotId) {

        for (Map<Location, String> reservations : reservationTable.values()) {
            reservations.entrySet().removeIf(e -> e.getValue().equals(robotId));
        }

    }

    private void reserveAction(Robot robot, Location loc) {

        int startTick = currentTick;

        int duration = moveTime(robot) * proporcionMovAccion;
        for (int t = 0; t < duration; t++) {

            int futureTick = startTick + t;

            reservationTable
                    .computeIfAbsent(futureTick, k -> new ConcurrentHashMap<>())
                    .put(loc, robot.getId());
        }
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

    private int moveTime(Robot r) {
        switch (r.getSpeed()) {
            case 1:
                return 5;
            case 2:
                return 3;
            case 3:
                return 1;
            default:
                throw new AssertionError();
        }
    }
}
