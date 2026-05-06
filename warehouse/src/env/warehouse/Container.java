package warehouse;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Representa un contenedor en el almacén.
 *
 * El "tipo" del contenedor es ahora una LISTA de etiquetas que pueden combinarse:
 *   - [standard]            paquete normal, sin atributos especiales
 *   - [fragile]             paquete frágil (los robots se mueven más despacio al cargarlo)
 *   - [urgent]              paquete urgente (sale en el deadline corto)
 *   - [urgent, fragile]     ambas etiquetas a la vez (sale en el deadline corto y el robot va más despacio)
 *
 * Las etiquetas son ortogonales: el motor de salida sólo se fija en si está
 * presente "urgent" para meter el paquete en deadline corto; y mov.asl sólo
 * se fija en si está "fragile" para aplicar la penalización del 15 %.
 */
public class Container {
    private final String id;
    private final int width;
    private final int height;
    private final double weight;
    private final List<String> tags; // lista de etiquetas (al menos una)
    private boolean picked;
    private String assignedShelf;
    private int x, y; // posición actual

    public Container(String id, int width, int height, double weight, List<String> tags) {
        this.id = id;
        this.width = width;
        this.height = height;
        this.weight = weight;
        // Defensiva: copia inmutable y nunca lista vacía (al menos "standard").
        List<String> copy = new ArrayList<>(tags);
        if (copy.isEmpty()) copy.add("standard");
        this.tags = Collections.unmodifiableList(copy);
        this.picked = false;
        this.assignedShelf = null;
        this.x = -1;
        this.y = -1;
    }

    // Getters
    public String getId() { return id; }
    public int getWidth() { return width; }
    public int getHeight() { return height; }
    public double getWeight() { return weight; }
    public List<String> getTags() { return tags; }
    public boolean isPicked() { return picked; }
    public String getAssignedShelf() { return assignedShelf; }
    public int getX() { return x; }
    public int getY() { return y; }

    public boolean hasTag(String tag) { return tags.contains(tag); }

    /**
     * Devuelve la representación Jason de la lista de etiquetas, p. ej.
     * "[urgent,fragile]". Sin espacios — los atom names deben ser válidos
     * y la unificación con .member/2 funciona igual.
     */
    public String getTagsAsAslList() {
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < tags.size(); i++) {
            if (i > 0) sb.append(",");
            sb.append(tags.get(i));
        }
        sb.append("]");
        return sb.toString();
    }

    // Setters
    public void setPicked(boolean picked) { this.picked = picked; }
    public void setAssignedShelf(String shelfId) { this.assignedShelf = shelfId; x=-1; y=-1;}
    public void setPosition(int x, int y) { this.x = x; this.y = y; }

    @Override
    public String toString() {
        return String.format("Container[%s: %dx%d, %.1fkg, %s]",
            id, width, height, weight, tags);
    }

    /**
     * Categoría de peso del contenedor
     */
    public String getWeightCategory() {
        if (weight <= 10) return "light";
        if (weight <= 30) return "medium";
        return "heavy";
    }

    /**
     * Calcula el área del contenedor
     */
    public int getArea() {
        return width * height;
    }
}
