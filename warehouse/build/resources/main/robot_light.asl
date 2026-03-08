!start.

+!start : true <-
    .print("🤖 Robot ligero iniciado - Capacidad: 10kg, 1x1 [Ágil]");
    .print("🔍 Iniciando secuencia de prueba de movimientos...");
    -+state(testing);
    !test_movement.
    //!work_cycle.
// Secuencia de prueba de movimientos (más rápida, zonas de estanterías pequeñas)
 

+!test_movement : true <-
    !go_to(mediumInit);
    .wait(1000);
    !go_to(shelf_9);
    .wait(1000);
    !go_to(lightInit).

+!go_to(Location) : .my_name(X) & not at(X,Location) <-
    move_to(Location);
    .wait(100);
    !go_to(Location).
    
+!go_to(Location) : at(X,Location) <-
    .print(" Posición alcanzada: ", Location);
    +state(idle).
