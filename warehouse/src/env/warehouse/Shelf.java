package warehouse;

import java.util.ArrayList;
import java.util.List;

/**
 * Representa una estantería en el almacén
 */
public class Shelf {

    private final String id;
    private final int x, y;
    private final int width, height;
    private final double maxWeight;
    private final int maxVolume;
    private final List<String> storedContainers;
    private double currentWeight;
    private int currentVolume;

    public Shelf(String id, int x, int y, int width, int height, double maxWeight, int maxVolume) {
        this.id = id;
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
        this.maxWeight = maxWeight;
        this.maxVolume = maxVolume;
        this.storedContainers = new ArrayList<>();
        this.currentWeight = 0;
        this.currentVolume = 0;
    }

    // Getters
    public String getId() {
        return id;
    }

    public int getX() {
        return x;
    }

    public int getY() {
        return y;
    }

    public int getWidth() {
        return width;
    }

    public int getHeight() {
        return height;
    }

    public double getMaxWeight() {
        return maxWeight;
    }

    public int getMaxVolume() {
        return maxVolume;
    }

    public List<String> getStoredContainers() {
        return new ArrayList<>(storedContainers);
    }

    public double getCurrentWeight() {
        return currentWeight;
    }

    public int getCurrentVolume() {
        return currentVolume;
    }

    /**
     * Verifica si el contenedor cabe en la estantería
     */
    public boolean canStore(Container container) {
        return (currentWeight + container.getWeight() <= maxWeight)
                && (currentVolume + container.getArea() <= maxVolume);
    }

    /**
     * Almacena un contenedor en la estantería
     */
    public boolean store(Container container) {
        if (!canStore(container)) {
            return false;
        }
        storedContainers.add(container.getId());
        currentWeight += container.getWeight();
        currentVolume += container.getArea();
        return true;
    }
 
    /**
     * Remueve un contenedor de la estantería
     */
    public boolean remove(String containerId, double weight, int volume) {
        if (storedContainers.remove(containerId)) {
            currentWeight -= weight;
            currentVolume -= volume;
            return true;
        }
        return false;
    }

    /**
     * Verifica si la estantería está llena
     */
    public boolean isFull() {
        return currentVolume >= maxVolume || currentWeight >= maxWeight;
    }

    /**
     * Obtiene el porcentaje de ocupación
     */
    public double getOccupancyPercentage() {
        double weightPercent = (currentWeight / maxWeight) * 100;
        double volumePercent = ((double) currentVolume / maxVolume) * 100;
        return Math.max(weightPercent, volumePercent);
    }

    @Override
    public String toString() {
        return String.format("Shelf[%s: @(%d,%d), %.1f/%.1fkg, %d/%d vol]",
                id, x, y, currentWeight, maxWeight, currentVolume, maxVolume);
    }
}
