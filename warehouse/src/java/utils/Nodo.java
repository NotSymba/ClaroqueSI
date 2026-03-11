package utils;
/**
 * Clase auxiliar para nuestra implementacion del Algoritmo A* de pathfinding
 */
public class Nodo implements Comparable<Nodo> {
    private final Location loc;
    private final int g;
    private final int f;
    private final Nodo padre;
    private int tick; // tick en el que se ocupará esta celda

    public Nodo(Location l, Nodo padre, int g, int h, int tick) {
        this.loc = l;
        this.g = g;
        this.f = g + h;
        this.padre = padre;
        this.tick = tick;
    }

    public Location getLoc(){
        return loc;
    }
    
    public Nodo getPadre(){
        return padre;
    }
  
    public int getG(){
        return g;
    }
    public int getF() {
    return this.f;
}
    public int getTick(){
        return tick;
    }

    @Override
    public int compareTo(Nodo otro) {
        return Integer.compare(this.f, otro.f);
    }
}