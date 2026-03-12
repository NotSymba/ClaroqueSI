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
container_queue([]).

// 1. Reaccionar a nuevo contenedor
+new_container(CId) : true <-
    .print("Nuevo contenedor: ", CId);
    get_container_info(CId).

// 2. Recibir info y marcar como pendiente
/*
+container_info(CId, W, H, Weight, Type) : true <-
    .print("Info: ", CId, " - ", Weight, "kg");
    +pending_container(CId, Weight, W, H).



+!taskcomplete(CId, ShelfId)[source(Robot)] : true <-
    .print("Robot ", Robot, " terminó con contenedor ", CId);
    +robot_available(Robot).

+pending_container(CId, Weight, W, H)
    : robot_available(Robot)
      & robot_capacity(Robot, MaxWeight, MaxW, MaxH, _)
      & Weight <= MaxWeight
      & W <= MaxW
      & H <= MaxH
<-
    .print("Asignando contenedor ", CId, " a ", Robot);

    // marcar al robot como ocupado
    -robot_available(Robot);

    // aquí decides la estantería según tu lógica
    ShelfId = shelf_9;  // o la que toque

    .send(Robot, achieve, task(CId, ShelfId)).
*/


// Opción A: Intentar asignación directa si hay un robot libre y con capacidad
+container_info(CId, W, H, Weight, Type) 
    : robot_available(Robot)
    & robot_capacity(Robot, MaxWeight, MaxW, MaxH, _)
    & Weight <= MaxWeight & W <= MaxW & H <= MaxH <-

    .print("¡Asignación directa! Enviando ", CId, " a ", Robot);
    -robot_available(Robot);
    
    // Aquí asignamos una estantería por defecto (puedes ajustar esta lógica luego)
        if(Weight<=20){
        ShelfId = shelf_4;
    
    }else{
        if(Weight> 20 & Weight <=50){
            ShelfId = shelf_5;
        }else{
            ShelfId = shelf_9;
        }
    } 
    .send(Robot, achieve, task(CId, ShelfId)).

// Opción B: Si el plan anterior falla (no hay robots libres o capaces), va a la cola
+container_info(CId, W, H, Weight, Type) : true <-
    .print("Ningún robot disponible para ", CId, ". Añadiendo a la cola...");
    !enqueue(pkg(CId, Weight, W, H, Type)).



+!enqueue(pkg(CId, Weight, W, H, urgent)) : container_queue(Q) <-
    -container_queue(Q);
    +container_queue([pkg(CId, Weight, W, H, urgent) | Q]);
    !try_assign.

+!enqueue(pkg(CId, Weight, W, H, Type)) : container_queue(Q) <-
    -container_queue(Q);
    .concat(Q, [pkg(CId, Weight, W, H, Type)], NewQ);
    +container_queue(NewQ);
    !try_assign.

+!append_end([], X, [X]) : true <- true.
+!append_end([H|T], X, [H|R]) : true <- !append_end(T, X, R).

+robot_available(_) : true <-
    !try_assign.


+!try_assign : container_queue([pkg(CId, Weight, W, H, Type) | Resto])
            & robot_available(Robot)
            & robot_capacity(Robot, MaxWeight, MaxW, MaxH, _)
            & Weight <= MaxWeight & W <= MaxW & H <= MaxH <-       

    -container_queue([pkg(CId, Weight, W, H, Type) | Resto]);
    +container_queue(Resto);

    -robot_available(Robot);

    .print("Asignando paquete ", Type, " ", CId, " a ", Robot);
    .send(Robot, achieve, task(CId, shelf_9));
    
    !try_assign.

+!try_assign <- true.


+!taskcomplete(CId, ShelfId)[source(Robot)] : true <-
    .print("Robot ", Robot, " terminó con contenedor ", CId);
    +robot_available(Robot).
