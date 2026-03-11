package warehouse;

/**
 * Representa un robot reponedor en el almacén
 */
public class Robot {
    private final String id;
    private final String type; // "light", "medium", "heavy"
    private final double maxWeight;
    private final int maxWidth;
    private final int maxHeight;
    private final int speed; // velocidad (alta=3, media=2, baja=1)
    private int x, y;
    private Container carriedContainer;
    private boolean busy;
    private String currentTask;
    
    
    public Robot(String id, String type, double maxWeight, int maxWidth, int maxHeight, int speed) {
        this.id = id;
        this.type = type;
        this.maxWeight = maxWeight;
        this.maxWidth = maxWidth;
        this.maxHeight = maxHeight;
        this.speed = speed;
        this.x = 0;
        this.y = 0;
        this.carriedContainer = null;
        this.busy = false;
        this.currentTask = null;
    }
    
    // Getters
    public String getId() { return id; }
    public String getType() { return type; }
    public double getMaxWeight() { return maxWeight; }
    public int getMaxWidth() { return maxWidth; }
    public int getMaxHeight() { return maxHeight; }
    public int getSpeed() { return speed; }
    public int getX() { return x; }
    public int getY() { return y; }
    public Container getCarriedContainer() { return carriedContainer; }
    public boolean isBusy() { return busy; }
    public String getCurrentTask() { return currentTask; }
    
    // Setters
    public void setPosition(int x, int y) { this.x = x; this.y = y; }
    public void setBusy(boolean busy) { this.busy = busy; }
    public void setCurrentTask(String task) { this.currentTask = task; }
    
    //get y modify del tiempo, esto es para el algoritmo de planificacion de ruta...
 
    /**
     * Verifica si el robot puede cargar un contenedor 
     */
    public boolean canCarry(Container container) {
        return container.getWeight() <= maxWeight &&
               container.getWidth() <= maxWidth &&
               container.getHeight() <= maxHeight;
    }
    
    /**
     * Recoge un contenedor
     */
    public boolean pickup(Container container) {
        System.out.println("**************************************************");
        if (carriedContainer != null || !canCarry(container)) {
            System.out.println("no lo recogio");
            return false;
        }
        this.carriedContainer = container;
        System.out.println("asignado: " + carriedContainer.getId());
    
        return true;
    }
    
    /**
     * Suelta el contenedor que está cargando
     */
    public Container drop() {
        Container container = this.carriedContainer;
        this.carriedContainer = null;
        return container;
    }
    
    /**
     * Verifica si el robot está cargando algo
     */
    public boolean isCarrying() {
        return carriedContainer != null;
    }
    
    /**
     * Se viene A* chato, así que esto sera util
     * Calcula la distancia Manhattan a un punto
     */
    public int distanceTo(int targetX, int targetY) {
        return Math.abs(x - targetX) + Math.abs(y - targetY);
    }
    
    @Override
    public String toString() {
        String carrying = isCarrying() ? carriedContainer.getId() : "none";
        return String.format("Robot[%s(%s): @(%d,%d), carrying=%s, busy=%s]", 
            id, type, x, y, carrying, busy);
    }


}
