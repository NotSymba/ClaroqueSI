{ include("mov.asl") }
{ include("work.asl") }

idlezone(4,3).
max_weight(30).
max_size(1, 2).
min_weight(10).
min_size(1, 1).

timePerMove(300).
priority(2).

// Solo acepta lo que light NO puede llevar (peso > 10 o tamaño > 1x1)
// pero que medium sí puede (peso <= 30 y tamaño <= 1x2)
can_i_manage(W, H, Weight) :-
    max_weight(MaxWeight) &
    max_size(MaxW, MaxH) &
    min_weight(MinWeight) &
    min_size(MinW, MinH) &
    Weight <= MaxWeight &
    W <= MaxW &
    H <= MaxH &
    (Weight > MinWeight | W > MinW | H > MinH).

!start.

+!start <-
    .print("Robot medium online. Esperando contenedores...");
    see.
