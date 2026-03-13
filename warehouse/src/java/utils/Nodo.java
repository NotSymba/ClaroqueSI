package utils;
/**
 * Clase auxiliar para nuestra implementacion del Algoritmo A* de pathfinding
 */
public class Nodo implements Comparable<Nodo> {
    private final Location loc;
    private final int g;
    private final int f;
    private final Nodo padre;

    public Nodo(Location l, Nodo padre, int g, int h) {
        this.loc = l;
        this.g = g;
        this.f = g + h;
        this.padre = padre;
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
    @Override
    public int compareTo(Nodo otro) {
        return Integer.compare(this.f, otro.f);
    }
}