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
 ******************************************************************************/

/* ============================================================================
 * CREENCIAS INICIALES - Base de Conocimiento
 * ============================================================================ */

/* Capacidades de los robots (Robot, MaxPeso, MaxW, MaxH, Velocidad) */
robot_capacity(robot_light, 10, 1, 1, 3).
robot_capacity(robot_medium, 30, 1, 2, 2).
robot_capacity(robot_heavy, 100, 2, 3, 1).

/* Robots disponibles se lo pasan los otros agentes */
/*
robot_available(robot_light).
robot_available(robot_medium).
robot_available(robot_heavy).
*/
/* Estadísticas */
total_containers_received(0).
total_tasks_assigned(0).
pending_containers(0).

/* ============================================================================
 * PLANES PRINCIPALES
 * ============================================================================ */

/* 1. Reaccionar a nuevo contenedor */
+new_container(CId)  <- 
    .print("Nuevo contenedor recibido: ", CId);
    get_container_info(CId).

/* 2. Recibir info del contenedor y clasificar */
+container_info(CId, W, H, Weight, Type) : true <- 
    .print("Info contenedor ", CId, ": ", Weight, "kg (", W, "x", H, ") - Tipo: ", Type);
    +pending_container(CId, Weight);
    .print("Clasificando contenedor ", CId);
    !try_assign(CId, W, H, Weight).

/* ============================================================================
 * FILTRADO DE ROBOTS
 * ============================================================================ */

/* Filtra robots disponibles que pueden manejar la carga */
+!available_robots(List, Weight, W, H) : true <- 
    .print("Buscando robots disponibles para peso ", Weight, "kg y tamaño ", W, "x", H);
    .findall(Robot, 
        (robot_available(Robot) & robot_capacity(Robot, MaxWeight, MaxW, MaxH, _Speed) & Weight <= MaxWeight & W <= MaxW & H <= MaxH),
        List).

/* Selecciona el robot más rápido de una lista */
+!select_fastest([], none) : true <- .print("No hay robots disponibles para seleccionar.").  // Caso base: no hay robots
+!select_fastest([Robot], Robot) : true <- .print("Un solo robot disponible, es el más rápido: ", Robot).  // Si hay un solo robot, es el más rápido
+!select_fastest([R1,R2], Fastest) : true <- 
    ?robot_capacity(R1, _, _, _, Speed1);
    ?robot_capacity(R2, _, _, _, Speed2);
    if(Speed1 >= Speed2) {
        Fastest = R1;
    } else {
        Fastest = R2;
    } 
    .print("Robots disponibles: ", [R1,R2], " - Seleccionado: ", Fastest).
+!select_fastest([R1,R2,R3], Fastest) : true <- 
    ?robot_capacity(R1, _, _, _, Speed1);
    ?robot_capacity(R2, _, _, _, Speed2);
    ?robot_capacity(R3, _, _, _, Speed3);
    if(Speed1 >= Speed2 & Speed1 >= Speed3) {
        Fastest = R1;
    }
    if(Speed2 >= Speed1 & Speed2 >= Speed3) {
        Fastest = R2;
    } 
    if(Speed3 >= Speed1 & Speed3 >= Speed2) {
        Fastest = R3;
    }
    .print("Robots disponibles: ", [R1,R2,R3], " - Seleccionado: ", Fastest).
 

/* ============================================================================
 * ASIGNACIÓN DE TAREAS
 * ============================================================================ */

/* Intentar asignar un robot a la tarea */
+!try_assign(CId, W, H, Weight) : true <- 
    !available_robots(Robots, Weight, W, H);
    if(.empty(Robots)) {
        .print("No hay robots disponibles para ", CId, ". Pendiente...");
        !fail;
    } 
    !select_fastest(Robots, BestRobot);
    !assign_task(BestRobot, CId).

//modificar para que espere y reasigne
+!assign_task(none, CId) <- 
    .print("Error: No se pudo asignar tarea para ", CId, " - No hay robots disponibles.");
    !fail.


+!assign_task(Robot, CId) : true <- 
    .print("Asignando contenedor ", CId, " a ", Robot);
    +assigned_task(Robot, CId);
    !notify_robot(Robot, CId).
/* Notificar al robot asignado para que inicie la tarea */
+!notify_robot(Robot, CId) : true <- 
    .print("Notificando a ", Robot, " sobre tarea ", CId);
    .send(Robot, achieve, work).

/*****************************************************************************
 * ESTADÍSTICAS Y MONITOREO
 * ============================================================================ */

 +!fail : true <-
    .print("No se pudo asignar tarea. Contenedor pendiente: ").