/*******************************************************************************
 * SCHEDULER - Agente Planificador y Coordinador de Tareas
 * 
 * Universidad de Vigo - Sistemas Inteligentes
 * Curso 2025-2026
 * 
 * RESPONSABILIDADES:
 *   1. Recibir notificaciones de nuevos contenedores
 *   2. Clasificar contenedores según peso, tamaño, tipo (urgente, frágil)
 *   3. Asignar tareas a robots según sus capacidades
 *   4. Optimizar la asignación para maximizar eficiencia
 *   5. Gestionar colas de contenedores pendientes
 *   6. Coordinar con supervisor para manejo de errores
 * 
 ******************************************************************************/

/* ============================================================================
 * CREENCIAS INICIALES - Base de Conocimiento
 * ============================================================================ */

/* Capacidades de los robots (debe coincidir con .mas2j) */
robot_capacity(robot_light, 10, 1, 1, 3).    // (Robot, MaxPeso, MaxW, MaxH, Velocidad)
robot_capacity(robot_medium, 30, 1, 2, 2).
robot_capacity(robot_heavy, 100, 2, 3, 1).

/* Estados de los robots */
robot_available(robot_light).
robot_available(robot_medium).
robot_available(robot_heavy).

/* Contadores y estadísticas */
total_containers_received(0).
total_tasks_assigned(0).
pending_containers(0).

// 1. Reaccionar a nuevo contenedor
+new_container(CId) : true <-
    .print("Nuevo contenedor: ", CId);
    get_container_info(CId).

// 2. Recibir info y marcar como pendiente
+container_info(CId, W, H, Weight, Type) : true <-
    .print("Info: ", CId, " - ", Weight, "kg");
    +pending_container(CId, Weight).


// 3. Clasificar contenedor pendiente y asignar robot
+pending_container(CId, Weight) : true <-
    .print("Clasificando ", CId);
    
    //findBestShelf(CId); 
    // Asignar a robot apropiado
    if (Weight <= 10) {
        .print("Asignando a robot_light"); 
        .send(robot_light, achieve, task(CId, shelf_4));
        // Nota: Esta es una simplificación
        // El scheduler debería verificar disponibilidad
    } else {
        if (Weight <= 30) {
            .print("Asignando a robot_medium");
            .send(robot_medium, achieve, task(CId, shelf_7));
        } else {
            .print("Asignando a robot_heavy");
            .send(robot_heavy, achieve, task(CId, shelf_9));
        }
    }.