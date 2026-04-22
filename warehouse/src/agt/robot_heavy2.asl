{ include("mov.asl") }
{ include("work.asl") }

idlezone(6,3).
max_weight(100).
max_size(2, 3).
min_weight(30).
min_size(1, 2).

timePerMove(500).
priority(3).

// heavy2 no recibe container_available directamente del scheduler; las
// tareas de entrada llegan vía assign_here desde robot_heavy (router).
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

// Asignación directa desde robot_heavy (router). Durante exit_in_progress
// se encola igualmente; el procesamiento está gated más abajo.
+assign_here(CId, W, H, Weight, Type) <-
    .print("Recibida asignación de ", CId, " desde robot_heavy");
    !enqueue(CId, W, H, Weight, Type);
    .abolish(assign_here(CId, _, _, _, _)).

// robot_heavy consulta estado para decidir reparto
+!report_status_to(Requester) :
    container_queue(Q) & state(S) <-
    .length(Q, L);
    .print("report_status_to ", Requester, " (cola=", L, ", estado=", S, ")");
    .send(Requester, tell, heavy_peer_status(L, S)).
