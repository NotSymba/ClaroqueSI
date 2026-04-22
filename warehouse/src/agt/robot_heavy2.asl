{ include("mov.asl") }
{ include("work.asl") }

idlezone(6,3).
max_weight(100).
max_size(2, 3).
min_weight(30).
min_size(1, 2).

timePerMove(500).
priority(3).

// Misma capacidad que robot_heavy. can_i_manage sigue definido aunque
// la decisión la centraliza robot_heavy (router) — lo mantenemos por si
// hiciera falta una comprobación local (p. ej. un assign_here erróneo).
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
    .print("Robot heavy2 online. A la espera de asignaciones de robot_heavy...");
    see.

// ─────────────────────────────────────────────────────────────
//  NUEVO CONTENEDOR
//  Este robot no decide por sí mismo: robot_heavy es el enrutador.
//  Si el scheduler nos enviase por error un container_info, lo
//  descartamos para no encolar dos veces.
// ─────────────────────────────────────────────────────────────
+container_info(CId, _, _, _, _) <-
    .abolish(container_info(CId, _, _, _, _)).

// robot_heavy nos asigna explícitamente un contenedor
+assign_here(CId, W, H, Weight, Type) <-
    .print("Recibida asignación de ", CId, " desde robot_heavy");
    !enqueue(CId, W, H, Weight, Type);
    .abolish(assign_here(CId, _, _, _, _)).

// robot_heavy nos consulta estado para decidir el reparto
+!report_status_to(Requester) :
    container_queue(Q) & state(S) <-
    .length(Q, L);
    .print("report_status_to ", Requester, " (cola=", L, ", estado=", S, ")");
    .send(Requester, tell, heavy_peer_status(L, S)).
