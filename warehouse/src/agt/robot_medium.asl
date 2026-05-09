{ include("mov.asl") }
{ include("work.asl") }

idlezone(4,3).
max_weight(30).
max_size(1, 2).

timePerMove(200).
priority(2).

robot_shelf_priority([shelf_6, shelf_7, shelf_2, shelf_3, shelf_4, shelf_9]).

// can_i_manage usa SOLO los topes propios. La regla "el más rápido capaz
// se queda con el paquete" se aplica en work.asl (+container_available)
// vía la guarda `not faster_capable`. Aquí declaramos que LIGHT (más
// rápido que medium) puede gestionar cualquier paquete que quepa en su
// capacidad propia (W<=1 & H<=1 & Weight<=10): si encaja ahí, medium se
// abstiene.
can_i_manage(W, H, Weight) :-
    max_weight(MaxWeight) &
    max_size(MaxW, MaxH) &
    Weight <= MaxWeight &
    W <= MaxW &
    H <= MaxH.

faster_capable(W, H, Weight) :-
    W <= 1 & H <= 1 & Weight <= 10.

!start.

+!start <-
    .print("Robot medium online. Esperando contenedores...");
    see.
