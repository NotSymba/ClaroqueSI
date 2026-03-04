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
    .wait(6000);
    !go_to(shelf9);
    .wait(6000);
    !go_to(entrance);
    .wait(6000);
    !go_to(mediumInit).

+!go_to(Location) : not at(Location) <-

    move_to(Location);
    .wait(300);
    !go_to(Location).
    
+!go_to(Location) : at(Location) <-
    .print(" Posición alcanzada: ", Location);
    +state(idle).
