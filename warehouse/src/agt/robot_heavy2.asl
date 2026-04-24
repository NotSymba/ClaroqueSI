{ include("mov.asl") }
{ include("work.asl") }

idlezone(6,3).
max_weight(100).
max_size(2, 3).
min_weight(30).
min_size(1, 2).

timePerMove(500).
priority(3).

// Prioridad propia: heavy2 prefiere el flanco DERECHO del almacén
// (shelves con x mayor) para repartir físicamente la carga con heavy,
// que prefiere el flanco izquierdo. shelf_9 sigue primero por ser la
// más lejana (y la de mayor capacidad).
robot_shelf_priority([shelf_9, shelf_7, shelf_6, shelf_4, shelf_3, shelf_2]).

// Peer simétrico de robot_heavy: ambos reciben container_available del
// scheduler y ejecutan decide_heavy_peer (work.asl). La coordinación es
// bilateral — ningún robot "manda", se ponen de acuerdo por carga actual.
is_router_robot.

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
    .print("Robot heavy2 online. Coordinando con robot_heavy (simétrico)...");
    see.
