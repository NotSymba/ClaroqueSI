+!start : true <-
    .print("Robot iniciado y listo").


+!handle_container(CId)[source(scheduler)] : true <-
    .print("Recibida orden del scheduler. Solicitando tarea al entorno para: ", CId);
    assignTask(CId).


+task(CId, ShelfId) : true <-
    -task(CId, ShelfId);
    .print("El entorno asignó la ruta: ", CId, " -> ", ShelfId);
    

    !go_to(CId);
    .wait(1500);

    pickup(CId);
    .print("Contenedor ", CId, " recogido físicamente.");
    .wait(1500);

    !deliver_container(CId, ShelfId).

+!deliver_container(CId, ShelfId) : true <-

    !go_to(ShelfId);
    .wait(1500);

    drop_at(ShelfId);
    
    .print("Contenedor depositado con éxito en ", ShelfId);


    taskcomplete(CId, ShelfId); 
    .print("Tarea marcada como completada en el sistema.");


    !go_to(mediumInit);

    .send(scheduler, achieve, taskcomplete(CId, ShelfId)).

-!deliver_container(CId, ShelfId) : true <-
    .print("¡Error! No se pudo depositar en ", ShelfId, ". Solicitando nueva estantería al entorno...");
    get_free_shelf(CId). 

+free_shelf(CId, NewShelf) : true <-
    -free_shelf(CId, NewShelf);

    .print("Nueva estantería alternativa recibida: ", NewShelf, ". Reintentando entrega...");
    !deliver_container(CId, NewShelf).


+!go_to(Location) : .my_name(X) & not at(X,Location) <-
    move_to(Location);
    .wait(225);
    !go_to(Location).

+!go_to(Location) : at(X,Location) <-
    .print("Posición alcanzada: ", Location);
    +state(idle).