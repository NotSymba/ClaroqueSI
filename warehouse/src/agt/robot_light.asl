{ include("mov.asl") }
{ include("work.asl") }

idlezone(3,3).
max_weight(10).
max_size(1, 1).

timePerMove(100).
priority(1).  // Más alta: el más rápido tiene preferencia de paso

// Prioridad propia de shelves para contenedores regulares (standard + fragile).
// Los urgentes siempre van a la urgent más cercana (ver pick_shelf_regular).
robot_shelf_priority([shelf_2, shelf_3, shelf_4, shelf_6, shelf_7, shelf_9]).

can_i_manage(W, H, Weight) :-
    max_weight(MaxWeight) &
    max_size(MaxW, MaxH) &
    Weight <= MaxWeight &
    W <= MaxW &
    H <= MaxH.

!start.

+!start <-
    .print("Robot light online. Esperando contenedores...");
    see.
