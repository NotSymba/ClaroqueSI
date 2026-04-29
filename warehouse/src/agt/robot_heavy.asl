{ include("mov.asl") }
{ include("work.asl") }

idlezone(5,3).
max_weight(100).
max_size(2, 3).
min_weight(30).
min_size(1, 2).

timePerMove(500).
priority(3).  // Más baja: cede el paso a los demás

robot_shelf_priority([shelf_9, shelf_6, shelf_7, shelf_2, shelf_3, shelf_4]).

// Flag compartido con heavy2: el plan genérico de container_available de
// work.asl NO dispara aquí. En su lugar se ejecuta el plan simétrico
// decide_heavy_peer definido en work.asl, que consulta al peer y decide
// quién encola según cola de pendientes + estado (idle/going_idle/busy),
// con desempate por nombre a favor de robot_heavy.
is_router_robot.

// Solo acepta lo que ni light ni medium pueden llevar
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
    .print("Robot heavy online. Coordinando con robot_heavy2 (simétrico)...");
    see.
