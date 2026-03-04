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
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Location location = (Location) o;
        return x == location.x && y == location.y;
    }

    @Override
    public int hashCode() {
        return Objects.hash(x, y);
    }
}