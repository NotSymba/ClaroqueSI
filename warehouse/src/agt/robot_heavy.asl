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
