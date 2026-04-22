{ include("mov.asl") }
{ include("work.asl") }

idlezone(3,3).
max_weight(10).
max_size(1, 1).

timePerMove(100).
priority(1).  // Más alta: el más rápido tiene preferencia de paso

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
