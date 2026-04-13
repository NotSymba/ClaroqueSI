package warehouse;

/**
 * Tipos de celdas en el almacén
 */
public enum CellType {
    EMPTY,          // Pasillo vacío
    ENTRANCE,       // Zona de entrada de contenedores
    CLASSIFICATION, // Zona de clasificación
    SHELF,          // Estantería
    BLOCKED,        // Celda bloqueada
    PACKAGE,        // Celda con un contenedor
    EXIT,           // Zona de salida de contenedores
    ROBOT           // Posición de un robot
}
