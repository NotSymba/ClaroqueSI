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

// ─────────────────────────────────────────────────────────────
//  NUEVO CONTENEDOR
//  container_info lo envía el scheduler vía .send(tell). Así se
//  entrega una única vez por contenedor y podemos abolirlo tras
//  procesarlo sin depender de que el entorno lo haga.
// ─────────────────────────────────────────────────────────────
+container_info(CId, W, H, Weight, Type) : can_i_manage(W, H, Weight) <-
    !enqueue(CId, W, H, Weight, Type);
    .abolish(container_info(CId, _, _, _, _)).

+container_info(CId, W, H, Weight, Type) <-
    .print("Contenedor ", CId, " fuera de mi capacidad, ignorado");
    .abolish(container_info(CId, _, _, _, _)).
