package utils;

import java.util.Objects;

/**
 * Clase auxiliar para representar una ubicación en el almacén
 */
public class Location {
    private final int x;
    private final int y;

    public Location(int x, int y) {
        this.x = x;
        this.y = y;
    }

    public int getX() { return x; }
    public int getY() { return y; }

    //distancia Manhattan entre dos ubicaciones
    public int distance(Location other) {
        return Math.abs(this.x - other.x) + Math.abs(this.y - other.y);
    }
 
    public boolean equals(Location o) {
 
        return x == o.x && y == o.y;
    }

    @Override
    public int hashCode() {
        return Objects.hash(x, y);
    }
}