{ include("mov.asl") }
{ include("work.asl") }

idlezone(5,3).
max_weight(100).
max_size(2, 3).
min_weight(30).
min_size(1, 2).

timePerMove(500).
priority(3).  // Más baja: cede el paso a los demás

// Solo acepta lo que ni light ni medium pueden llevar (peso > 30 o tamaño > 1x2)
// pero que heavy sí puede (peso <= 100 y tamaño <= 2x3)
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
//  NUEVO CONTENEDOR
//  robot_heavy actúa como enrutador para el par heavy/heavy2. El
//  scheduler envía container_info sólo a robot_heavy; aquí se decide
//  quién se queda el paquete y, si corresponde, se reenvía a heavy2.
// ─────────────────────────────────────────────────────────────
+container_info(CId, W, H, Weight, Type) : can_i_manage(W, H, Weight) <-
    !decide_heavy(CId, W, H, Weight, Type);
    .abolish(container_info(CId, _, _, _, _)).

+container_info(CId, W, H, Weight, Type) <-
    .print("Contenedor ", CId, " fuera de mi capacidad, ignorado");
    .abolish(container_info(CId, _, _, _, _)).

// Pregunta a heavy2 por su estado y aplica la regla de asignación.
// Regla (MiLen = mi cola, OLen = cola de heavy2):
//   MiLen  <  OLen                         → yo
//   MiLen  >  OLen                         → heavy2
//   empate, yo idle                        → yo
//   empate, yo busy y heavy2 idle          → heavy2
//   empate, ambos ocupados o ambos idle    → yo (tiebreaker fijo)
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

// (1) Mi cola más corta → yo
+!route_heavy(CId, W, H, Weight, Type, MyL, _, OtherL, _) : MyL < OtherL <-
    .print("Tomo ", CId, " (mi cola ", MyL, " < heavy2 ", OtherL, ")");
    !enqueue(CId, W, H, Weight, Type).

// (2) Cola de heavy2 más corta → heavy2
+!route_heavy(CId, W, H, Weight, Type, MyL, _, OtherL, _) : MyL > OtherL <-
    .print("Asigno ", CId, " a heavy2 (mi cola ", MyL, " > heavy2 ", OtherL, ")");
    .send(robot_heavy2, tell, assign_here(CId, W, H, Weight, Type)).

// (3a) Empate y yo idle → yo
+!route_heavy(CId, W, H, Weight, Type, _, idle, _, _) <-
    .print("Empate y yo idle → tomo ", CId);
    !enqueue(CId, W, H, Weight, Type).

// (3b) Empate y yo going_idle → yo
+!route_heavy(CId, W, H, Weight, Type, _, going_idle, _, _) <-
    .print("Empate y yo going_idle → tomo ", CId);
    !enqueue(CId, W, H, Weight, Type).

// (4a) Empate, yo busy y heavy2 idle → heavy2
+!route_heavy(CId, W, H, Weight, Type, _, _, _, idle) <-
    .print("Empate y heavy2 idle → asigno ", CId);
    .send(robot_heavy2, tell, assign_here(CId, W, H, Weight, Type)).

// (4b) Empate, yo busy y heavy2 going_idle → heavy2
+!route_heavy(CId, W, H, Weight, Type, _, _, _, going_idle) <-
    .print("Empate y heavy2 going_idle → asigno ", CId);
    .send(robot_heavy2, tell, assign_here(CId, W, H, Weight, Type)).

// (5) Ambos ocupados → tiebreaker fijo: yo
+!route_heavy(CId, W, H, Weight, Type, _, _, _, _) <-
    .print("Empate ambos ocupados, tiebreaker → tomo ", CId);
    !enqueue(CId, W, H, Weight, Type).

// Por si heavy2 alguna vez nos pide estado (simetría futura)
+!report_status_to(Requester) :
    container_queue(Q) & state(S) <-
    .length(Q, L);
    .send(Requester, tell, heavy_peer_status(L, S)).
