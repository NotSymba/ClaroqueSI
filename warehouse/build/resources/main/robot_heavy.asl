+!start : true <-
    .print("Robot iniciado y listo").


+!handle_container(CId)[source(scheduler)] : true <-
    .print("Recibida orden del scheduler. Solicitando tarea al entorno para: ", CId);
    assignTask(CId).


+task(CId, ShelfId) : true <-
    -task(CId, ShelfId);
    .print("El entorno asignó la ruta: ", CId, " -> ", ShelfId);
    

    !go_to(entrance);
    .wait(2000);

    pickup(CId);
    .print("Contenedor ", CId, " recogido físicamente.");
    .wait(2000);

    !go_to(ShelfId);
    .wait(2000);

    drop_at(ShelfId);
    .print("Contenedor depositado en ", ShelfId);


    taskcomplete(CId, ShelfId);
    .print("Tarea marcada como completada en el sistema.");


    !go_to(heavyInit); 
    

    .send(scheduler, achieve, taskcomplete(CId, ShelfId)).


+!go_to(Location) : .my_name(X) & not at(X,Location) <-
    move_to(Location);
    .wait(375);
    !go_to(Location).

+!go_to(Location) : at(X,Location) <-
    .print("Posición alcanzada: ", Location);
    +state(idle).