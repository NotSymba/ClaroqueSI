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
