package warehouse;

import com.sun.source.doctree.LiteralTree;
import jason.asSyntax.*;
import jason.environment.grid.GridWorldModel;

import utils.Location;
import warehouse.Robot;
import warehouse.Container;
import warehouse.Shelf;

import java.util.*;
import java.util.concurrent.*;

public class WarehouseModel extends GridWorldModel {

    int proporcionMovAccion = 3;
    int speed = 75;

    private static final int GRID_WIDTH = 20;
    private static final int GRID_HEIGHT = 15;

    private CellType[][] grid;
    private Map<String, Robot> robots;
    private Map<String, Container> containers;
    private Map<String, Shelf> shelves;
    private ConcurrentLinkedQueue<Container> pendingContainers;
    private Map<String, String> taskAssignments;

    // Todas las posiciones válidas de entrada (sin duplicados)
    private final List<Location> allEntranceLocations = Arrays.asList(
            new Location(5, 0), new Location(6, 0), new Location(7, 0),
            new Location(5, 1), new Location(6, 1), new Location(7, 1)
    );
    // Pool de slots de entrada libres (sin paquete encima)
    private final ConcurrentLinkedDeque<Location> freeEntranceSlots = new ConcurrentLinkedDeque<>();

    private int containerCounter = 0;
    private int totalContainersProcessed = 0;
    private int totalErrors = 0;
    private long startTime;

    public WarehouseModel() {
        super(GRID_WIDTH, GRID_HEIGHT, 3);

        grid = new CellType[GRID_WIDTH][GRID_HEIGHT];
        robots = new ConcurrentHashMap<>();
        containers = new ConcurrentHashMap<>();
        shelves = new ConcurrentHashMap<>();
        pendingContainers = new ConcurrentLinkedQueue<>();
        taskAssignments = new ConcurrentHashMap<>();

        initializeGrid();
        initializeRobots();
        initializeShelves();

        // Todos los slots de entrada comienzan libres
        freeEntranceSlots.addAll(allEntranceLocations);

        startTime = System.currentTimeMillis();

        System.out.println("Warehouse environment initialized");
        System.out.println("Grid size: " + GRID_WIDTH + "x" + GRID_HEIGHT);
        System.out.println("Robots: " + robots.size());
        System.out.println("Shelves: " + shelves.size());
    }

    // -------------------------------------------------------------------------
    // INICIALIZACIÓN
    // -------------------------------------------------------------------------
    private void initializeGrid() {
        for (int x = 0; x < GRID_WIDTH; x++) {
            for (int y = 0; y < GRID_HEIGHT; y++) {
                grid[x][y] = CellType.EMPTY;
            }
        }

        for (int x = 0; x < 3; x++) {
            for (int y = 0; y < 2; y++) {
                grid[x][y] = CellType.EXIT;
            }
        }

        for (int x = 3; x < 5; x++) {
            for (int y = 0; y < 2; y++) {
                grid[x][y] = CellType.CLASSIFICATION;
            }
        }

        for (int x = 5; x < 8; x++) {
            for (int y = 0; y < 2; y++) {
                grid[x][y] = CellType.ENTRANCE;
            }
        }
    }

    private void initializeRobots() {
        Robot light = new Robot("robot_light", "light", 10, 1, 1, 3);
        light.setPosition(3, 3);
        robots.put("robot_light", light);

        Robot medium = new Robot("robot_medium", "medium", 30, 1, 2, 2);
        medium.setPosition(4, 3);
        robots.put("robot_medium", medium);

        Robot heavy = new Robot("robot_heavy", "heavy", 100, 2, 3, 1);
        heavy.setPosition(5, 3);
        robots.put("robot_heavy", heavy);
        // Segundo robot Heavy — idéntico en capacidades a robot_heavy.
        // Se coordina con robot_heavy vía mensajes (ver robot_heavy.asl).
        Robot heavy2 = new Robot("robot_heavy2", "heavy", 100, 2, 3, 1);
        heavy2.setPosition(6, 3);
        robots.put("robot_heavy2", heavy2);
    }

    private void initializeShelves() {
        int shelfId = 1;

        for (int x = 10; x < 18; x += 2) {
            Shelf shelf = new Shelf("shelf_" + shelfId++, x, 2, 2, 2, 50, 8);
            shelves.put(shelf.getId(), shelf);
            grid[x][2] = CellType.SHELF;
            grid[x + 1][2] = CellType.SHELF;
            grid[x][3] = CellType.SHELF;
            grid[x + 1][3] = CellType.SHELF;
        }

        for (int x = 10; x < 18; x += 3) {
            Shelf shelf = new Shelf("shelf_" + shelfId++, x, 6, 3, 2, 100, 12);
            shelves.put(shelf.getId(), shelf);
            for (int dx = 0; dx < 3; dx++) {
                grid[x + dx][6] = CellType.SHELF;
                grid[x + dx][7] = CellType.SHELF;
            }
        }

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

    // -------------------------------------------------------------------------
    // GENERACIÓN DE CONTENEDORES
    // -------------------------------------------------------------------------
    /**
     * Genera un nuevo contenedor en un slot de entrada libre. Devuelve null si
     * no hay slots disponibles.
     */
    public Container newContainer() {
        return newContainer(java.util.Collections.emptySet());
    }

    /**
     * Genera un nuevo contenedor evitando los tipos indicados en blockedTypes
     * (ciclo de salida activo). Si los tres tipos están bloqueados devuelve
     * null sin consumir slot.
     */
    public Container newContainer(Set<String> blockedTypes) {
        if (freeEntranceSlots.isEmpty()) {
            System.out.println("No free entrance slots available!");
            totalErrors++;
            return null;
        }
        if (blockedTypes.contains("standard")
                && blockedTypes.contains("fragile")
                && blockedTypes.contains("urgent")) {
            // Todos los tipos bloqueados — no se genera nada.
            return null;
        }

        Container container = generateRandomContainerFair(blockedTypes);
        if (container == null) {
            return null;
        }

        containers.put(container.getId(), container);
        pendingContainers.offer(container);
        System.out.println("New container generated: " + container);
        return container;
    }

    private Container generateRandomContainerFair() {
        return generateRandomContainerFair(java.util.Collections.emptySet());
    }

    private Container generateRandomContainerFair(Set<String> blockedTypes) {
        // Consume un slot libre del pool
        Location slot = freeEntranceSlots.poll();
        if (slot == null) {
            return null;
        }

        Random rand = new Random();
        String id = "container_" + (++containerCounter);

        int width, height;
        double weight;

        double category = rand.nextDouble();

        if (category < 0.33) {
            width = 1;
            height = 1;
            weight = 5 + rand.nextDouble() * 5;
        } else if (category < 0.66) {
            int[][] sizes = {{1, 1}, {1, 2}};
            int[] size = sizes[rand.nextInt(sizes.length)];
            width = size[0];
            height = size[1];
            weight = 10 + rand.nextDouble() * 20;
        } else {
            int[][] sizes = {{1, 1}, {1, 2}, {2, 2}, {2, 3}};
            int[] size = sizes[rand.nextInt(sizes.length)];
            width = size[0];
            height = size[1];
            weight = 30 + rand.nextDouble() * 70;
        }

        // Sorteo ponderado estándar 0.70 / fragile 0.15 / urgent 0.15,
        // descartando tipos bloqueados y renormalizando pesos.
        Map<String, Double> weights = new LinkedHashMap<>();
        if (!blockedTypes.contains("standard")) weights.put("standard", 0.70);
        if (!blockedTypes.contains("fragile"))  weights.put("fragile",  0.15);
        if (!blockedTypes.contains("urgent"))   weights.put("urgent",   0.15);
        double totalW = 0.0;
        for (Double w : weights.values()) totalW += w;

        double r = rand.nextDouble() * totalW;
        double acc = 0.0;
        String type = null;
        for (Map.Entry<String, Double> e : weights.entrySet()) {
            acc += e.getValue();
            if (r <= acc) {
                type = e.getKey();
                break;
            }
        }
        if (type == null) {
            // No debería ocurrir si blockedTypes no contiene los tres tipos.
            freeEntranceSlots.offer(slot);
            return null;
        }

        grid[slot.getX()][slot.getY()] = CellType.PACKAGE;

        Container container = new Container(id, width, height, weight, type);
        container.setPosition(slot.getX(), slot.getY());
        return container;
    }

    // -------------------------------------------------------------------------
    // ACCIONES DE AGENTES
    // -------------------------------------------------------------------------
    /**
     * Mueve un paquete de la zona de entrada a una posición de la zona de
     * clasificación. action: moveToProcessing(containerId, destX, destY)
     *
     * La celda origen vuelve a CellType.ENTRANCE y su slot se devuelve al pool
     * libre. La celda destino pasa a CellType.PACKAGE.
     *
     * Códigos de retorno: 0 = ok 1 = robot o contenedor no encontrado 2 = el
     * contenedor ya fue recogido o no está en zona de entrada 3 = destino
     * ocupado (no es CLASSIFICATION libre) 4 = destino fuera de la zona de
     * clasificación 5 = error inesperado
     */
    public int moveToProcessing(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            int destX = Integer.parseInt(action.getTerm(1).toString().replace("\"", ""));
            int destY = Integer.parseInt(action.getTerm(2).toString().replace("\"", ""));

            Container container = containers.get(containerId);
            Robot robot = robots.get(agName);

            if (robot == null || container == null) {
                totalErrors++;
                return 1;
            }

            if (container.isPicked()) {
                totalErrors++;
                return 2;
            }

            int srcX = container.getX();
            int srcY = container.getY();

            // El paquete debe estar en la celda marcada como PACKAGE dentro de la zona de entrada
            if (grid[srcX][srcY] != CellType.PACKAGE) {
                totalErrors++;
                return 2;
            }

            // El destino debe ser una celda de clasificación libre
            if (grid[destX][destY] != CellType.CLASSIFICATION) {
                totalErrors++;
                return 3;
            }

            // Verificar que el destino está dentro de los límites de la zona de clasificación
            if (destX < 3 || destX >= 5 || destY < 0 || destY >= 2) {
                totalErrors++;
                return 4;
            }

            // Restaurar origen a ENTRANCE y devolver slot al pool
            grid[srcX][srcY] = CellType.ENTRANCE;
            freeEntranceSlots.offer(new Location(srcX, srcY));

            // Colocar paquete en destino
            grid[destX][destY] = CellType.PACKAGE;
            container.setPosition(destX, destY);

            System.out.println("Container " + containerId + " moved from entrance ("
                    + srcX + "," + srcY + ") to processing (" + destX + "," + destY + ")");
            return 0;

        } catch (Exception e) {
            e.printStackTrace();
            totalErrors++;
            return 5;
        }
    }

    /**
     * El robot recoge un contenedor desde la zona de
     * clasificación/procesamiento. action: pickUp(containerId)
     *
     * La celda del paquete vuelve a CellType.CLASSIFICATION.
     *
     * Códigos de retorno: 0 = ok 1 = robot o contenedor no encontrado 2 = robot
     * ya lleva algo 3 = robot demasiado lejos 4 = error inesperado
     */
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

            if (robot.distanceTo(container.getX(), container.getY()) > 1) {
                totalErrors++;
                return 3;
            }

            int cx = container.getX();
            int cy = container.getY();

            // Restaurar la celda según su zona original
            boolean esEntrada = allEntranceLocations.stream()
                    .anyMatch(loc -> loc.getX() == cx && loc.getY() == cy);

            if (esEntrada) {
                grid[cx][cy] = CellType.ENTRANCE;
                freeEntranceSlots.offer(new Location(cx, cy));
            } else {
                grid[cx][cy] = CellType.CLASSIFICATION;
            }

            robot.pickup(container);
            container.setPicked(true);

            System.out.println("Robot " + agName + " picked up " + containerId
                    + " from (" + container.getX() + "," + container.getY() + ")");
            return 0;

        } catch (Exception e) {
            totalErrors++;
            e.printStackTrace();
            return 4;
        }
    }

    /**
     * Mueve un paquete de su celda actual a una celda libre de clasificación.
     * No razona sobre accesibilidad: el caller (scheduler) decide destX/destY.
     *
     * Códigos: 0 = ok, 1 = contenedor no encontrado, 2 = contenedor no válido
     * (recogido o no está en PACKAGE), 3 = destino no es CLASSIFICATION libre,
     * 4 = destino fuera de zona de clasificación, 5 = error inesperado.
     */
    public int relocateContainer(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            int destX = Integer.parseInt(action.getTerm(1).toString().replace("\"", ""));
            int destY = Integer.parseInt(action.getTerm(2).toString().replace("\"", ""));

            Container container = containers.get(containerId);
            if (container == null) {
                totalErrors++;
                return 1;
            }
            if (container.isPicked()) {
                totalErrors++;
                return 2;
            }

            int srcX = container.getX();
            int srcY = container.getY();
            if (grid[srcX][srcY] != CellType.PACKAGE) {
                totalErrors++;
                return 2;
            }

            if (destX < 3 || destX >= 5 || destY < 0 || destY >= 2) {
                totalErrors++;
                return 4;
            }
            if (grid[destX][destY] != CellType.CLASSIFICATION) {
                totalErrors++;
                return 3;
            }

            boolean srcEsEntrada = allEntranceLocations.stream()
                    .anyMatch(loc -> loc.getX() == srcX && loc.getY() == srcY);
            if (srcEsEntrada) {
                grid[srcX][srcY] = CellType.ENTRANCE;
                freeEntranceSlots.offer(new Location(srcX, srcY));
            } else {
                grid[srcX][srcY] = CellType.CLASSIFICATION;
            }

            grid[destX][destY] = CellType.PACKAGE;
            container.setPosition(destX, destY);

            System.out.println("Container " + containerId + " relocated from ("
                    + srcX + "," + srcY + ") to (" + destX + "," + destY + ")");
            return 0;
        } catch (Exception e) {
            e.printStackTrace();
            totalErrors++;
            return 5;
        }
    }

    /**
     * El robot deposita el contenedor que carga en una celda de clasificación.
     * action: drop_in_processing(DestX, DestY)
     */
    public int dropAtProcessing(String agName, Structure action) {
        try {
            Robot robot = robots.get(agName);
            if (robot == null) {
                totalErrors++;
                return 1;
            }
            if (!robot.isCarrying()) {
                totalErrors++;
                return 2;
            }

            int destX = -1;
            int destY = -1;
            int minDst = 9999;
            for (int x = 3; x < 5; x++) {
                for (int y = 0; y < 2; y++) {
                    if (grid[x][y] == CellType.CLASSIFICATION) {
                        int dst = robot.distanceTo(x, y);
                        if (dst <= 1 && dst < minDst) {
                            destX = x; destY = y; minDst = dst;
                        }
                    }
                }
            }
            if (destX == -1) {
                // If not adjacent, just find any empty one
                for (int x = 3; x < 5; x++) {
                    for (int y = 0; y < 2; y++) {
                        if (grid[x][y] == CellType.CLASSIFICATION) {
                            int dst = robot.distanceTo(x, y);
                            if (dst < minDst) {
                                destX = x; destY = y; minDst = dst;
                            }
                        }
                    }
                }
            }
            
            if (destX == -1) {
                totalErrors++;
                return 3; // No empty classification cells
            }

            Container container = robot.getCarriedContainer();
            String cid = container.getId();
            
            grid[destX][destY] = CellType.PACKAGE;
            container.setPosition(destX, destY);
            
            robot.drop();
            container.setPicked(false);
            container.setAssignedShelf(null);
            
            System.out.println("Robot " + agName + " dropped " + cid + " at processing (" + destX + "," + destY + ")");
            return 0;
        } catch (Exception e) {
            e.printStackTrace();
            totalErrors++;
            return 6;
        }
    }

    /**
     * El robot deposita el contenedor que carga en una celda de la zona de
     * salida (EXIT, x in [0..2], y in [0..1]). El contenedor sale definitivamente
     * del sistema.
     *
     * action: drop_at_exit(ExitX, ExitY)
     *
     * Códigos: 0 = ok, 1 = robot no encontrado, 2 = robot no carga nada,
     * 3 = celda no es EXIT, 4 = fuera de zona de salida, 5 = robot no adyacente,
     * 6 = error inesperado.
     */
    public int dropAtExit(String agName, Structure action) {
        try {
            int destX = Integer.parseInt(action.getTerm(0).toString().replace("\"", ""));
            int destY = Integer.parseInt(action.getTerm(1).toString().replace("\"", ""));

            Robot robot = robots.get(agName);
            if (robot == null) {
                totalErrors++;
                return 1;
            }
            if (!robot.isCarrying()) {
                totalErrors++;
                return 2;
            }
            if (destX < 0 || destX >= 3 || destY < 0 || destY >= 2) {
                totalErrors++;
                return 4;
            }
            if (grid[destX][destY] != CellType.EXIT) {
                totalErrors++;
                return 3;
            }
            if (robot.distanceTo(destX, destY) > 1) {
                totalErrors++;
                return 5;
            }

            Container container = robot.getCarriedContainer();
            String cid = container.getId();
            robot.drop();
            containers.remove(cid);
            totalContainersProcessed++;
            System.out.println("Container " + cid + " exited warehouse via ("
                    + destX + "," + destY + ")");
            return 0;
        } catch (Exception e) {
            e.printStackTrace();
            totalErrors++;
            return 6;
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

            if (!isAdjacentToShelf(agName, shelfId)) {
                totalErrors++;
                return 3;
            }

            Container container = robot.getCarriedContainer();
            System.out.println("Intentando depositar " + container.getId() + " en " + shelf.getId());

            if (!shelf.canStore(container)) {
                totalErrors++;
                return 4;
            }

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

    /**
     * El robot recoge un contenedor que está almacenado en una estantería.
     * action: retrieve(containerId)
     *
     * Comprueba que el contenedor está asignado a una estantería y que el
     * robot está adyacente a ella. Actualiza peso y volumen de la estantería
     * al sacar el paquete.
     *
     * Códigos: 0 = ok, 1 = robot/contenedor no encontrado, 2 = robot ya carga,
     * 3 = robot no adyacente al shelf, 4 = el contenedor no está en un shelf,
     * 5 = el robot no puede cargar el contenedor, 6 = error inesperado.
     */
    public int retrieveFromShelf(String agName, Structure action) {
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

            String shelfId = container.getAssignedShelf();
            if (shelfId == null) {
                totalErrors++;
                return 4;
            }

            Shelf shelf = shelves.get(shelfId);
            if (shelf == null) {
                totalErrors++;
                return 1;
            }

            if (!isAdjacentToShelf(agName, shelfId)) {
                totalErrors++;
                return 3;
            }

            if (!robot.canCarry(container)) {
                totalErrors++;
                return 5;
            }

            shelf.remove(containerId, container.getWeight(), container.getArea());

            container.setPicked(true);
            container.setAssignedShelf(null);

            robot.pickup(container);

            System.out.println("Robot " + agName + " retrieved " + containerId
                    + " from shelf " + shelfId);
            return 0;

        } catch (Exception e) {
            e.printStackTrace();
            totalErrors++;
            return 6;
        }
    }

    public int steap(String agName, Structure action) {
        try {
            Robot robot = robots.get(agName);
            int x = Integer.parseInt(action.getTerm(0).toString().replace("\"", ""));
            int y = Integer.parseInt(action.getTerm(1).toString().replace("\"", ""));

            if (hayAgenteEn(x, y)) {
                totalErrors++;
                System.out.println("error de ruta: agente estatico en ruta");
                return 3;
            }
            robot.setPosition(x, y);
            if (escacharPaquete(agName) != null) {
                return 5;
            }
            return 0;

        } catch (Exception e) {
            e.printStackTrace();
            totalErrors++;
            return 4;
        }
    }

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

        robot.setBusy(false);
        taskAssignments.remove(containerId, agName);
        return true;
    }

    // -------------------------------------------------------------------------
    // CONSULTAS / PERCEPTOS
    // -------------------------------------------------------------------------
    public Literal get_shelf_status(String agName, Structure action) {
        try {
            String shelfId = action.getTerm(0).toString().replace("\"", "");
            Shelf shelf = shelves.get(shelfId);

            if (shelf == null) {
                totalErrors++;
                return null;
            }

            return Literal.parseLiteral(
                    "shelf_info("
                    + shelfId + ","
                    + shelf.getMaxWeight() + ","
                    + shelf.getCurrentWeight() + ","
                    + shelf.getMaxVolume() + ","
                    + shelf.getCurrentVolume() + ")"
            );

        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public Literal getFinalShelf(String itemId) {
         Shelf s = shelves.get(itemId);
        if (s != null) {
            return Literal.parseLiteral(
                    "locationF(" + itemId + "," + (s.getX() + s.getWidth()) + "," + (s.getY() + s.getHeight())+ ")"
            );
        }
        return null;
    }

    

    public Literal getLocation(String itemId) {
        if (itemId.startsWith("shelf_")) {
            Shelf s = shelves.get(itemId);
            if (s != null) {
                return Literal.parseLiteral(
                        "location(" + itemId + "," + s.getX() + "," + s.getY() + ")"
                );
            }
            return null;
        }
        if (itemId.startsWith("container_")) {
            Container c = containers.get(itemId);
            if (c != null) {
                return Literal.parseLiteral(
                        "location(" + itemId + "," + c.getX() + "," + c.getY() + ")"
                );
            }
        }
        if (itemId.startsWith("robot")) {
            Robot r = robots.get(itemId);
            if (r != null) {
                return Literal.parseLiteral(
                        "location(" + itemId + "," + r.getX() + "," + r.getY() + ")"
                );
            }
        }
        return null;
    }

    public Literal getContainerInfo(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            Container container = containers.get(containerId);

            if (container == null) {
                totalErrors++;
                return null;
            }

            return Literal.parseLiteral(
                    "container_info(" + containerId + ","
                    + container.getWidth() + ","
                    + container.getHeight() + ","
                    + container.getWeight() + ","
                    + container.getType() + ")"
            );

        } catch (Exception e) {
            totalErrors++;
            e.printStackTrace();
            return null;
        }
    }

    public String assignTask(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            String shelfId = action.getTerm(1).toString().replace("\"", "");
            Container container = containers.get(containerId);
            Shelf shelf = shelves.get(shelfId);
            Robot robot = robots.get(agName);

            if (robot == null) {
                totalErrors++;
                return "null_robot";
            }

            if (taskAssignments.containsKey(containerId)) {
                totalErrors++;
                return "already_assigned";
            }

            if (robot.isBusy() || robot.isCarrying()) {
                totalErrors++;
                return "busy";
            }

            if (container == null) {
                totalErrors++;
                return "null_container";
            }

            if (!robot.canCarry(container)) {
                totalErrors++;
                return "cannot_carry";
            }

            if (shelf == null) {
                totalErrors++;
                return "null_shelf";
            }

            taskAssignments.put(container.getId(), agName);
            robot.setBusy(true);
            robot.setCurrentTask(container.getId());

            System.out.println("Task assigned to " + agName + ": " + container.getId() + " -> " + shelf.getId());
            pendingContainers.remove(container);

            return Literal.parseLiteral(
                    "task(" + container.getId() + "," + shelf.getId() + ")").toString();

        } catch (Exception e) {
            e.printStackTrace();
            totalErrors++;
            return "error";
        }
    }

    // -------------------------------------------------------------------------
    // UTILIDADES
    // -------------------------------------------------------------------------
    public String getStatistics() {
        long elapsedTime = (System.currentTimeMillis() - startTime) / 1000;
        return String.format(
                "Time: %ds | Processed: %d | Pending: %d | Errors: %d",
                elapsedTime, totalContainersProcessed, pendingContainers.size(), totalErrors
        );
    }

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

    /**
     * Devuelve las casillas accesibles (no-SHELF) adyacentes a un shelf.
     * Son las celdas que bordean el rectángulo del shelf y que están dentro
     * del grid y NO son SHELF.
     */
    public Literal getShelfAdjacentCells(String shelfId) {
        Shelf shelf = shelves.get(shelfId);
        if (shelf == null) return null;

        int minX = shelf.getX();
        int maxX = shelf.getX() + shelf.getWidth() - 1;
        int minY = shelf.getY();
        int maxY = shelf.getY() + shelf.getHeight() - 1;

        StringBuilder sb = new StringBuilder("shelf_adjacent(" + shelfId + ",[");
        boolean first = true;

        // Borde superior (y = minY - 1)
        if (minY - 1 >= 0) {
            for (int x = minX; x <= maxX; x++) {
                if (grid[x][minY - 1] != CellType.SHELF) {
                    if (!first) sb.append(",");
                    sb.append("pos(").append(x).append(",").append(minY - 1).append(")");
                    first = false;
                }
            }
        }
        // Borde inferior (y = maxY + 1)
        if (maxY + 1 < GRID_HEIGHT) {
            for (int x = minX; x <= maxX; x++) {
                if (grid[x][maxY + 1] != CellType.SHELF) {
                    if (!first) sb.append(",");
                    sb.append("pos(").append(x).append(",").append(maxY + 1).append(")");
                    first = false;
                }
            }
        }
        // Borde izquierdo (x = minX - 1)
        if (minX - 1 >= 0) {
            for (int y = minY; y <= maxY; y++) {
                if (grid[minX - 1][y] != CellType.SHELF) {
                    if (!first) sb.append(",");
                    sb.append("pos(").append(minX - 1).append(",").append(y).append(")");
                    first = false;
                }
            }
        }
        // Borde derecho (x = maxX + 1)
        if (maxX + 1 < GRID_WIDTH) {
            for (int y = minY; y <= maxY; y++) {
                if (grid[maxX + 1][y] != CellType.SHELF) {
                    if (!first) sb.append(",");
                    sb.append("pos(").append(maxX + 1).append(",").append(y).append(")");
                    first = false;
                }
            }
        }

        sb.append("])");
        return Literal.parseLiteral(sb.toString());
    }

    public boolean isAdjacentToShelf(String robotID, String shelfID) {
        Robot robot = robots.get(robotID);
        Shelf shelf = shelves.get(shelfID);
        int rx = robot.getX();
        int ry = robot.getY();

        int minX = shelf.getX();
        int maxX = shelf.getX() + shelf.getWidth() - 1;
        int minY = shelf.getY();
        int maxY = shelf.getY() + shelf.getHeight() - 1;

        if (rx == minX - 1 && ry >= minY && ry <= maxY) {
            return true;
        }
        if (rx == maxX + 1 && ry >= minY && ry <= maxY) {
            return true;
        }
        if (ry == minY - 1 && rx >= minX && rx <= maxX) {
            return true;
        }
        if (ry == maxY + 1 && rx >= minX && rx <= maxX) {
            return true;
        }

        return false;
    }

    private boolean hayAgenteEn(int x, int y) {
        for (Robot robot : robots.values()) {
            if (robot.getX() == x && robot.getY() == y) {
                return true;
            }
        }
        return false;
    }

    /**
     * Si el robot pisa un paquete no recogido, lo destruye y restaura la celda.
     */
    private String escacharPaquete(String rid) {
        Robot r = robots.get(rid);
        for (Container c : containers.values()) {
            if (c.getX() == r.getX() && c.getY() == r.getY() && !c.isPicked()) {
                int cx = c.getX();
                int cy = c.getY();

                // Determinar a qué tipo vuelve la celda
                boolean esEntrada = allEntranceLocations.stream()
                        .anyMatch(loc -> loc.getX() == cx && loc.getY() == cy);

                if (esEntrada) {
                    grid[cx][cy] = CellType.ENTRANCE;
                    freeEntranceSlots.offer(new Location(cx, cy));
                } else {
                    grid[cx][cy] = CellType.CLASSIFICATION;
                }

                containers.remove(c.getId());
                System.out.println("Paquete " + c.getId() + " escachado por " + r.getId());
                return c.getId();
            }
        }
        return null;
    }
}
