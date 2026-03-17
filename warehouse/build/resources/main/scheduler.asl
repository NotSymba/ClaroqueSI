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
//total_containers_received(0).
//total_tasks_assigned(0).
//pending_containers(0).
container_queue([]).

fastest_available(Robot, Weight,W, H) :-
    robot_available(Robot)
    & robot_capacity(Robot, MaxWeight, MaxW, MaxH, Speed)
    & Weight <= MaxWeight & W <= MaxW & H <= MaxH
    & not (
        robot_available(Other)
        & robot_capacity(Other, MW2, MW3, MW4, Speed2)
        & Weight <= MW2 & W <= MW3 & H <= MW4
        & Speed2 > Speed
    ).

+new_container(CId) : true <-
    .print("Nuevo contenedor detectado en el entorno: ", CId);
    get_container_info(CId).


+container_info(CId, W, H, Weight, Type) 
    : fastest_available(Robot, Weight,W, H) <-

    .print("Asignando paquete ", Type, " ", CId, "peso:",Weight," de ",W,"x",H, " a ", Robot);
    -robot_available(Robot);

    .send(Robot, achieve, handle_container(CId)).
    


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

+robot_available(_) : true <-
    !try_assign.

+!try_assign : container_queue([pkg(CId, Weight, W, H, Type) | Resto])
            & fastest_available(Robot, Weight, W, H) <-
 
    -container_queue(_);
    +container_queue(Resto);
    -robot_available(Robot);

    .print("Asignando paquete ", Type, " ", CId, "peso:",Weight," de ",W,"x",H, " a ", Robot);
    .send(Robot, achieve, handle_container(CId));
    
    !try_assign.

+!try_assign <- true.


+!taskcomplete(CId, ShelfId)[source(Robot)] : true <-
    .print("Robot ", Robot, " terminó con contenedor ", CId);
    +robot_available(Robot).
