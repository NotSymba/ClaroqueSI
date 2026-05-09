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
import java.util.concurrent.atomic.AtomicInteger;

public class WarehouseModel extends GridWorldModel {

    int proporcionMovAccion = 3;
    int speed = 75;

    private static final int GRID_WIDTH = 20;
    private static final int GRID_HEIGHT = 15;

    private CellType[][] grid;
    private Map<String, Robot> robots;
    private Map<String, Container> containers;
    private Map<String, Shelf> shelves;
    private AtomicInteger PendingContainerCounter = new AtomicInteger(0);
    private int totalContainers =0;

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
    private AtomicInteger totalErrors = new AtomicInteger(0);
    private long startTime;

    public WarehouseModel() {
        super(GRID_WIDTH, GRID_HEIGHT, 3);

        grid = new CellType[GRID_WIDTH][GRID_HEIGHT];
        robots = new ConcurrentHashMap<>();
        containers = new ConcurrentHashMap<>();
        shelves = new ConcurrentHashMap<>();
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
     * Genera un nuevo contenedor evitando los GRUPOS de salida indicados en
     * blockedGroups. Los grupos son:
     *   - "urgent": paquetes con la etiqueta urgent (puro o combinado con fragile)
     *   - "normal": paquetes sin la etiqueta urgent (standard puro o fragile puro)
     * Si los dos grupos están bloqueados devuelve null sin consumir slot.
     */
    public Container newContainer(Set<String> blockedGroups) {
        if (freeEntranceSlots.isEmpty()) {
            System.out.println("No free entrance slots available!");
            totalErrors.incrementAndGet();
            return null;
        }
        if (blockedGroups.contains("urgent") && blockedGroups.contains("normal")) {
            // Ambos grupos bloqueados — no se genera nada.
            return null;
        }

        Container container = generateRandomContainerFair(blockedGroups);
        if (container == null) {
            return null;
        }

        containers.put(container.getId(), container);
        PendingContainerCounter.incrementAndGet();
        totalContainers++;
        System.out.println("New container generated: " + container);
        return container;
    }

    private Container generateRandomContainerFair() {
        return generateRandomContainerFair(java.util.Collections.emptySet());
    }

    private Container generateRandomContainerFair(Set<String> blockedGroups) {
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

        // ───────────────────────────────────────────────────────
        // SORTEO DE ETIQUETAS (no son tipos disjuntos: son tags que
        // pueden combinarse). Probabilidades:
        //   [standard]         0.70    (sin atributos especiales)
        //   [urgent]           0.13875 (urgente puro)
        //   [fragile]          0.13875 (frágil puro)
        //   [urgent, fragile]  0.0225 (= 0.15 * 0.15) — el combo
        //
        // Se conserva la probabilidad de "standard" (0.70) tal como pidió
        // el usuario; el combo urgent+fragile sale 0.0225, y el resto
        // (0.30 - 0.0225 = 0.2775) se reparte por igual entre urgent puro
        // y fragile puro (0.13875 cada uno). Suma = 1.0.
        //
        // Bloqueos por grupo (ciclo de salida activo):
        //   - "urgent"  bloqueado  ⇒  no se generan combos con urgent
        //   - "normal"  bloqueado  ⇒  no se generan combos sin urgent
        //                              (standard puro ni fragile puro)
        // Renormalizamos pesos descartando combos bloqueados.
        // ───────────────────────────────────────────────────────
        boolean blockUrgent = blockedGroups.contains("urgent");
        boolean blockNormal = blockedGroups.contains("normal");

        Map<List<String>, Double> tagWeights = new LinkedHashMap<>();
        if (!blockNormal) tagWeights.put(Arrays.asList("standard"),         0.70);
        if (!blockUrgent) tagWeights.put(Arrays.asList("urgent"),           0.13875);
        if (!blockNormal) tagWeights.put(Arrays.asList("fragile"),          0.13875);
        if (!blockUrgent) tagWeights.put(Arrays.asList("urgent", "fragile"), 0.0225);

        double totalW = 0.0;
        for (Double w : tagWeights.values()) totalW += w;

        double r = rand.nextDouble() * totalW;
        double acc = 0.0;
        List<String> chosenTags = null;
        for (Map.Entry<List<String>, Double> e : tagWeights.entrySet()) {
            acc += e.getValue();
            if (r <= acc) {
                chosenTags = e.getKey();
                break;
            }
        }
        if (chosenTags == null) {
            // No debería ocurrir si no están todos los grupos bloqueados.
            freeEntranceSlots.offer(slot);
            return null;
        }

        if (hayAgenteEn(slot.getX(), slot.getY())) {
            freeEntranceSlots.offer(slot);
            return null;
        }

        grid[slot.getX()][slot.getY()] = CellType.PACKAGE;
        Container container = new Container(id, width, height, weight, chosenTags);
        container.setPosition(slot.getX(), slot.getY());
        return container;
    }

    // -------------------------------------------------------------------------
    // ACCIONES DE AGENTES
    // -------------------------------------------------------------------------
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
                totalErrors.incrementAndGet();
                return 1;
            }

            if (robot.isCarrying()) {
                totalErrors.incrementAndGet();
                return 2;
            }

            if (robot.distanceTo(container.getX(), container.getY()) > 1) {
                totalErrors.incrementAndGet();
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
            totalErrors.incrementAndGet();
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
                totalErrors.incrementAndGet();
                return 1;
            }
            if (container.isPicked()) {
                totalErrors.incrementAndGet();
                return 2;
            }

            int srcX = container.getX();
            int srcY = container.getY();
            if (grid[srcX][srcY] != CellType.PACKAGE) {
                totalErrors.incrementAndGet();
                return 2;
            }

            if (destX < 3 || destX >= 5 || destY < 0 || destY >= 2) {
                totalErrors.incrementAndGet();
                return 4;
            }
            if (grid[destX][destY] != CellType.CLASSIFICATION) {
                totalErrors.incrementAndGet();
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
            totalErrors.incrementAndGet();
            return 5;
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
                totalErrors.incrementAndGet();
                return 1;
            }
            if (!robot.isCarrying()) {
                totalErrors.incrementAndGet();
                return 2;
            }
            if (destX < 0 || destX >= 3 || destY < 0 || destY >= 2) {
                totalErrors.incrementAndGet();
                return 4;
            }
            if (grid[destX][destY] != CellType.EXIT) {
                totalErrors.incrementAndGet();
                return 3;
            }
            if (robot.distanceTo(destX, destY) > 1) {
                totalErrors.incrementAndGet();
                return 5;
            }

            Container container = robot.getCarriedContainer();
            String cid = container.getId();
            robot.drop();
            containers.remove(cid);
            totalContainersProcessed++;
            PendingContainerCounter.decrementAndGet();
            System.out.println("Container " + cid + " exited warehouse via ("
                    + destX + "," + destY + ")");
            return 0;
        } catch (Exception e) {
            e.printStackTrace();
            totalErrors.incrementAndGet();
            return 6;
        }
    }

    public int dropContainer(String agName, Structure action) {
        try {
            String shelfId = action.getTerm(0).toString().replace("\"", "");

            Robot robot = robots.get(agName);
            Shelf shelf = shelves.get(shelfId);

            if (robot == null || shelf == null) {
                totalErrors.incrementAndGet();
                return 1;
            }

            if (!robot.isCarrying()) {
                totalErrors.incrementAndGet();
                return 2;
            }

            if (!isAdjacentToShelf(agName, shelfId)) {
                totalErrors.incrementAndGet();
                return 3;
            }

            Container container = robot.getCarriedContainer();
            System.out.println("Intentando depositar " + container.getId() + " en " + shelf.getId());

            if (!shelf.canStore(container)) {
                totalErrors.incrementAndGet();
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
                totalErrors.incrementAndGet();
                return 1;
            }

            if (robot.isCarrying()) {
                totalErrors.incrementAndGet();
                return 2;
            }

            String shelfId = container.getAssignedShelf();
            if (shelfId == null) {
                totalErrors.incrementAndGet();
                return 4;
            }

            Shelf shelf = shelves.get(shelfId);
            if (shelf == null) {
                totalErrors.incrementAndGet();
                return 1;
            }

            if (!isAdjacentToShelf(agName, shelfId)) {
                totalErrors.incrementAndGet();
                return 3;
            }

            if (!robot.canCarry(container)) {
                totalErrors.incrementAndGet();
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
            totalErrors.incrementAndGet();
            return 6;
        }
    }

    public int steap(String agName, Structure action) {
        try {
            Robot robot = robots.get(agName);
            int x = Integer.parseInt(action.getTerm(0).toString().replace("\"", ""));
            int y = Integer.parseInt(action.getTerm(1).toString().replace("\"", ""));

            if (hayAgenteEn(x, y)) {
                totalErrors.incrementAndGet() ;
                System.out.println("error de ruta: agente estatico en ruta");
                return 3;
            }
            robot.setPosition(x, y);
            // El aplastamiento de un contenedor lo gestiona el caller
            // (executeSteap) llamando a escacharPaquete tras el move; así
            // el éxito del paso no depende del estado de la celda destino
            // y la intención de moverse no se pierde por un splash.
            return 0;

        } catch (Exception e) {
            e.printStackTrace();
            totalErrors.incrementAndGet();
            return 4;
        }
    }

    // -------------------------------------------------------------------------
    // CONSULTAS / PERCEPTOS
    // -------------------------------------------------------------------------   

    public Literal getContainerInfo(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            Container container = containers.get(containerId);

            if (container == null) {
                totalErrors.incrementAndGet();
                return null;
            }

            // El "tipo" se serializa como lista de etiquetas Jason:
            //   container_info(c1, 1, 1, 5.0, [urgent,fragile])
            return Literal.parseLiteral(
                    "container_info(" + containerId + ","
                    + container.getWidth() + ","
                    + container.getHeight() + ","
                    + container.getWeight() + ","
                    + container.getTagsAsAslList() + ")"
            );

        } catch (Exception e) {
            totalErrors.incrementAndGet();
            e.printStackTrace();
            return null;
        }
    }

    // -------------------------------------------------------------------------
    // UTILIDADES
    // -------------------------------------------------------------------------
    public String getStatistics() {
        long elapsedTime = (System.currentTimeMillis() - startTime) / 1000;
        return String.format(
                "Time: %ds | total: %d |Processed: %d | Pending: %d | Errors: %d",
                elapsedTime, totalContainers, totalContainersProcessed, PendingContainerCounter.get(), totalErrors.get()
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
        return PendingContainerCounter.get();
    }
 
    public int getTotalContainers() {
        return totalContainers;
    }

    public int getTotalErrors() {
        return totalErrors.get();
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
     * Devuelve el contenedor destruido (para notificar a los agentes) o null
     * si la celda no contenía un paquete sin recoger.
     */
    public Container escacharPaquete(String rid) {
        Robot r = robots.get(rid);
        if (r == null) {
            return null;
        }
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
                return c;
            }
        }
        return null;
    }
}
