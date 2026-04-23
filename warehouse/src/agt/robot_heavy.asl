{ include("mov.asl") }
{ include("work.asl") }

idlezone(5,3).
max_weight(100).
max_size(2, 3).
min_weight(30).
min_size(1, 2).

timePerMove(500).
priority(3).  // Más baja: cede el paso a los demás

// Esta flag hace que el plan +container_available de work.asl NO dispare
// aquí: en su lugar se aplica el plan específico de router que sigue.
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
    .print("Robot heavy online. Coordinando con robot_heavy2...");
    see.

// ─────────────────────────────────────────────────────────────
//  ROUTER HEAVY/HEAVY2
//  El scheduler anuncia container_available sólo a robot_heavy
//  (no a heavy2); aquí se decide quién se queda el paquete y, si
//  corresponde, se reenvía con assign_here a robot_heavy2.
// ─────────────────────────────────────────────────────────────
// Durante un ciclo de salida el router sigue encolando/ruteando como
// siempre — el procesamiento efectivo está gated por exit_in_progress
// en check_idle/process_next (ver work.asl).
+container_available(CId, W, H, Weight, Type) :
        can_i_manage(W, H, Weight) <-
    !decide_heavy(CId, W, H, Weight, Type);
    .abolish(container_available(CId, _, _, _, _)).

+container_available(CId, _, _, _, _) <-
    .abolish(container_available(CId, _, _, _, _)).

// Regla de reparto (MiLen = mi cola, OLen = cola de heavy2):
//   MiLen < OLen                         → yo
//   MiLen > OLen                         → heavy2
//   empate y yo idle                     → yo
//   empate, yo going_idle, heavy2 idle   → heavy2 (heavy2 ya está parado, más cerca)
//   empate y yo going_idle               → yo
//   empate y heavy2 idle/going_idle      → heavy2
//   empate ambos ocupados                → yo (tiebreaker fijo)
+!decide_heavy(CId, W, H, Weight, Type) :
    container_queue(MyQ) & state(MyS) <-
    .length(MyQ, MyL);
    .abolish(heavy_peer_status(_, _));
    .my_name(Me);
    .print("decide_heavy ", CId, " — mi_cola=", MyL, ", mi_estado=", MyS, ", preguntando a heavy2...");
    .send(robot_heavy2, achieve, report_status_to(Me));
    .wait({+heavy_peer_status(_, _)}, 2000, _);
    if (heavy_peer_status(OtherL, OtherS)) {
        .abolish(heavy_peer_status(_, _));
        .print("heavy2 respondió: cola=", OtherL, ", estado=", OtherS);
        !route_heavy(CId, W, H, Weight, Type, MyL, MyS, OtherL, OtherS)
    } else {
        .print("heavy2 no responde, me quedo ", CId);
        !enqueue(CId, W, H, Weight, Type)
    }.

+!route_heavy(CId, W, H, Weight, Type, MyL, _, OtherL, _) : MyL < OtherL <-
    .print("Tomo ", CId, " (mi cola ", MyL, " < heavy2 ", OtherL, ")");
    !enqueue(CId, W, H, Weight, Type).

+!route_heavy(CId, W, H, Weight, Type, MyL, _, OtherL, _) : MyL > OtherL <-
    .print("Asigno ", CId, " a heavy2 (mi cola ", MyL, " > heavy2 ", OtherL, ")");
    .send(robot_heavy2, tell, assign_here(CId, W, H, Weight, Type)).

+!route_heavy(CId, W, H, Weight, Type, _, idle, _, _) <-
    .print("Empate y yo idle → tomo ", CId);
    !enqueue(CId, W, H, Weight, Type).

+!route_heavy(CId, W, H, Weight, Type, _, going_idle, _, idle) <-
    .print("Empate: yo going_idle pero heavy2 idle → asigno ", CId, " (heavy2 más cerca)");
    .send(robot_heavy2, tell, assign_here(CId, W, H, Weight, Type)).

+!route_heavy(CId, W, H, Weight, Type, _, going_idle, _, _) <-
    .print("Empate y yo going_idle → tomo ", CId);
    !enqueue(CId, W, H, Weight, Type).

+!route_heavy(CId, W, H, Weight, Type, _, _, _, idle) <-
    .print("Empate y heavy2 idle → asigno ", CId);
    .send(robot_heavy2, tell, assign_here(CId, W, H, Weight, Type)).

+!route_heavy(CId, W, H, Weight, Type, _, _, _, going_idle) <-
    .print("Empate y heavy2 going_idle → asigno ", CId);
    .send(robot_heavy2, tell, assign_here(CId, W, H, Weight, Type)).

+!route_heavy(CId, W, H, Weight, Type, _, _, _, _) <-
    .print("Empate ambos ocupados, tiebreaker → tomo ", CId);
    !enqueue(CId, W, H, Weight, Type).

+!report_status_to(Requester) :
    container_queue(Q) & state(S) <-
    .length(Q, L);
    .send(Requester, tell, heavy_peer_status(L, S)).
