/*******************************************************************************
 * AGENTE: Robot pesado
 * DESCRIPCIÓN: Robot robusto diseñado para manejar cargas pesadas en el almacén.
 * CAPACIDAD: 100 kg
 * TAMAÑO MÁXIMO: 2×3
 * VELOCIDAD: Baja (1)
 * Posicion de inicio(heavyInit): (3,3)
 ********************************************************************************
 CREENCIA INICIALES:
    - robot_type(heavy): tipo de robot
    - max_weight(100): peso máximo que puede cargar
    - max_size(2,3): tamaño máximo de contenedor
 ********************************************************************************/
//ESTADO INICIAL DEL ROBOT
state(idle).         // Estados posibles: , idle, moving, picking, carrying, dropping
carrying(none).      // Contenedor que está cargando
timeperMove(100).     // Tiempo que tarda en moverse a una ubicación adyacente (en ms)
!start.

+!start : true <-
    .print("🤖 Robot pesado iniciado - Capacidad: 100kg, 2x3 [Robusto]");
    .print("🔍 Iniciando secuencia de prueba de movimientos...");
    .wait(500);
    .send(scheduler, tell,robot_available(robot_heavy)).
    

// Ciclo de trabajo principal del robot 
// El shceduler se encargará de asignar tareas al robot, y este responderá a ellas según su estado actual
+!work(Cid) : state(idle) <-
    .send(scheduler, untell,robot_available(robot_heavy));
    assignTask(Cid). //decirle al entorno que al robot le asigne siguiente tarea disponible.
+!work(Cid) : not state(idle) <-
    .print("Estoy realizando una taream, por favor espere...").


//al recibir una tarea
+task(CId, ShelfId) : state(idle) <-
    .print("Tarea asignada: Transportar ", CId, " a ", ShelfId);
    -+state(working); // cambiar estado a trabajando
    -+carrying(CId);
    !execute_task(CId, ShelfId).

//Ejecutar la tarea asignada, que consiste en ir a la zona de entrada, recoger el contenedor, transportarlo a la estantería asignada y depositarlo allí. Luego volver a estado idle para esperar nueva tarea.   
+!execute_task(CId, ShelfId) : true <-
    .print("Iniciando tarea: ", CId);
    
    // Fase 1: Ir al área de entrada (donde están los contenedores)
    .print("Fase 1: Moviéndose al área de entrada");
    !go_to(entrance);
    .wait(1000);
    
    // Fase 2: Recoger el contenedor
    .print("Fase 2: Recogiendo contenedor ", CId);
    -+state(picking);
    pickup(CId);
    .wait(1000);
    
    // Fase 3: Navegar hacia la estantería
    .print("Fase 3: Transportando a estantería ", ShelfId);
    -+state(carrying);
    !go_to(ShelfId);
    
    // Fase 4: Depositar el contenedor
    .print("📥 Fase 4: Depositando en ", ShelfId);
    -+state(dropping);
    drop_at(ShelfId);
    .wait(1000);
    
    // Fase 5: Completar y volver a idle
    .print("Tarea completada: ", CId);
    -+state(working); 
    -+carrying(none);
    -task(CId, ShelfId);
    // Fase 6: volver a posición inicial
    .print("Volviendo a posición inicial...");
    !go_to(heavyInit);
    -+state(idle);
    taskcomplete(CId, ShelfId);
    .send(scheduler, tell,robot_available(robot_heavy)).

//go_to para moverse a una ubicación específica, se llama recursivamente hasta llegar a la ubicación deseada
+!go_to(Location) : .my_name(X) & not at(X,Location) <-
    move_to(Location);
    .wait(155);
    !go_to(Location).
//cuando se llega a la ubicación deseada, se cambia el estado a idle y se imprime un mensaje de confirmación
+!go_to(Location) : at(X,Location) <-
    .print(" Posición alcanzada: ", Location);
    +state(idle).

+!test_movement : true <-
    !go_to(heavyInit);
    .wait(2000);
    !go_to(shelf_1);
    .wait(2000);
    !go_to(heavyInit).
 