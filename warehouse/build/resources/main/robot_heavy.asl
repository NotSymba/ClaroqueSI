+!start : true <-
    .print("Robot pesado iniciado").


+!task(CId, ShelfId) : true <-
    .print("Ejecutando tarea: ", CId);
    
    // Paso 1: Ir al contenedor (simplificado)
    !go_to(entrance);  // Posición aproximada
    .wait(2000);
    
    // Paso 2: Recoger
    pickup(CId);
    .wait(2000);
    
    // Paso 3: Ir a estantería (simplificado)
    !go_to(ShelfId);
    .wait(2000);
    
    // Paso 4: Depositar
    drop_at(ShelfId);

    
    .print("Tarea completada");

    //!go_to(heavyInit);
    .send(scheduler, achieve, taskcomplete(CId, ShelfId)).

+!go_to(Location) : .my_name(X) & not at(X,Location) <-
    move_to(Location);
    .wait(375);
    !go_to(Location).
    
+!go_to(Location) : at(X,Location) <-
    .print(" Posición alcanzada: ", Location);
    +state(idle).