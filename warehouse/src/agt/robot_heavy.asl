/*
!start.

+!start : true <-
    .print("🤖 Robot ligero iniciado - Capacidad: 10kg, 1x1 [Ágil]");
    .print("🔍 Iniciando secuencia de prueba de movimientos...");
    -+state(testing);
    !test_movement.
    //!work_cycle.
// Secuencia de prueba de movimientos (más rápida, zonas de estanterías pequeñas)
 

+!test_movement : true <-
    !go_to(heavyInit);
    .wait(2000);
    !go_to(shelf_1);
    .wait(2000);
    !go_to(heavyInit).

+!go_to(Location) : .my_name(X) & not at(X,Location) <-

    move_to(Location);
    .wait(500);
    !go_to(Location).
    
+!go_to(Location) : .my_name(X) & at(X,Location) <-
    .print(" Posición alcanzada: ", Location);
    +state(idle).
*/

+!start : true <-
    .print("Robot pesado iniciado").


+!task(CId, ShelfId) : true <-
    .print("Ejecutando tarea: ", CId);
    
    // Paso 1: Ir al contenedor (simplificado)
    !go_to(entrance);  // Posición aproximada
    .wait(1000);
    
    // Paso 2: Recoger
    pickup(CId);
    .wait(1000);
    
    // Paso 3: Ir a estantería (simplificado)
    !go_to(ShelfId);
    .wait(1000);
    
    // Paso 4: Depositar
    drop_at(ShelfId);

    taskcomplete(CId, ShelfId);
    .print("Tarea completada");

    !go_to(heavyInit).


+!go_to(Location) : .my_name(X) & not at(X,Location) <-
    move_to(Location);
    .wait(100);
    !go_to(Location).
    
+!go_to(Location) : at(X,Location) <-
    .print(" Posición alcanzada: ", Location);
    +state(idle).