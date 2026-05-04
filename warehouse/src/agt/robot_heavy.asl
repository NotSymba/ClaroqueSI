{ include("mov.asl") }
{ include("work.asl") }

idlezone(5,3).
max_weight(100).
max_size(2, 3).

timePerMove(500).
priority(3).  // Más baja: cede el paso a los demás

robot_shelf_priority([shelf_9, shelf_6, shelf_7, shelf_2, shelf_3, shelf_4]).

// Flag compartido con heavy2: el plan genérico de container_available de
// work.asl NO dispara aquí. En su lugar se ejecuta el plan simétrico
// decide_heavy_peer definido en work.asl, que consulta al peer y decide
// quién encola según cola de pendientes + estado (idle/going_idle/busy),
// con desempate por nombre a favor de robot_heavy.
is_router_robot.

// can_i_manage usa solo los topes propios. La regla "el más rápido capaz
// se queda" la aplica work.asl con `not faster_capable`. faster_capable
// declara que MEDIUM (más rápido que heavy) puede gestionar el paquete:
// si encaja en la capacidad de medium (W<=1 & H<=2 & Weight<=30) los
// heavy se abstienen. Si la guarda falla y el paquete sigue siendo
// manejable por heavy, decide_heavy_peer reparte entre heavy y heavy2.
can_i_manage(W, H, Weight) :-
    max_weight(MaxWeight) &
    max_size(MaxW, MaxH) &
    Weight <= MaxWeight &
    W <= MaxW &
    H <= MaxH.

faster_capable(W, H, Weight) :-
    W <= 1 & H <= 2 & Weight <= 30.

!start.

+!start <-
    .print("Robot heavy online. Coordinando con robot_heavy2 (simétrico)...");
    see.
