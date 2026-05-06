{ include("mov.asl") }
{ include("work.asl") }

idlezone(5,3).
max_weight(100).
max_size(2, 3).

timePerMove(500).
priority(3).  // Más baja: cede el paso a los demás

robot_shelf_priority([shelf_9, shelf_6, shelf_7, shelf_2, shelf_3, shelf_4]).

// Flag compartido con heavy2: las guardas `not is_router_robot` de
// work.asl impiden que el plan genérico de container_available dispare
// aquí. En su lugar se ejecuta el plan simétrico decide_heavy_peer
// definido más abajo (duplicado intencionalmente entre robot_heavy.asl
// y robot_heavy2.asl), que consulta al peer y decide quién encola según
// cola de pendientes + estado (idle/going_idle/busy), con desempate por
// nombre a favor de robot_heavy.
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

// ═════════════════════════════════════════════════════════════
// COORDINACIÓN SIMÉTRICA robot_heavy ↔ robot_heavy2
//
// Bloque DUPLICADO entre robot_heavy.asl y robot_heavy2.asl (ambos
// llevan `is_router_robot`, así que las guardas `not is_router_robot`
// de work.asl evitan que sus planes genéricos disparen). Cualquier
// cambio aquí debe replicarse en robot_heavy2.asl.
//
// El scheduler anuncia container_available a AMBOS heavy. Cada uno
// consulta al peer su estado y aplica la MISMA regla determinista:
//   1) cola de pendientes más corta → gana
//   2) empate de cola: el no-ocupado (idle | going_idle) gana sobre busy
//   3) empate de cola y ambos no-ocupados: idle (en zona) gana sobre
//      going_idle (yendo a zona)
//   4) empate absoluto (cola y estado iguales): robot_heavy gana
// El perdedor simplemente descarta — no envía assign_here. Así un solo
// robot encola cada paquete, sin solapamientos ni mensajes extra.
//
// Si el peer no responde en 2s (caso degenerado) nos lo quedamos para
// no perder el paquete.
// ═════════════════════════════════════════════════════════════
+container_available(CId, W, H, Weight, Tags) :
        is_router_robot &
        can_i_manage(W, H, Weight) &
        not faster_capable(W, H, Weight) <-
    !decide_heavy_peer(CId, W, H, Weight, Tags);
    .abolish(container_available(CId, _, _, _, _)).

+container_available(CId, _, _, _, _) : is_router_robot <-
    .abolish(container_available(CId, _, _, _, _)).

+!decide_heavy_peer(CId, W, H, Weight, Tags) :
        container_queue(MyQ) & state(MyS) <-
    .length(MyQ, MyL);
    !heavy_peer_name(PeerName);
    .my_name(Me);
    .abolish(heavy_peer_info(_, _));
    .print("decide_heavy_peer ", CId, " — mi cola=", MyL, ", estado=", MyS);
    .send(PeerName, achieve, report_heavy_info(Me));
    .wait({+heavy_peer_info(_, _)}, 2000, _);
    if (heavy_peer_info(PeerL, PeerS)) {
        .abolish(heavy_peer_info(_, _));
        .print("Peer ", PeerName, ": cola=", PeerL, ", estado=", PeerS);
        !route_symmetric(CId, W, H, Weight, Tags, MyL, MyS, PeerL, PeerS)
    } else {
        .print("Peer ", PeerName, " no responde — me quedo ", CId);
        !enqueue(CId, W, H, Weight, Tags)
    }.

+!heavy_peer_name(robot_heavy2) : .my_name(robot_heavy).
+!heavy_peer_name(robot_heavy)  : .my_name(robot_heavy2).

+!report_heavy_info(Requester) :
        container_queue(Q) & state(S) <-
    .length(Q, L);
    .send(Requester, tell, heavy_peer_info(L, S)).

// Regla simétrica. Los dos heavy ejecutan esta misma cadena con los
// valores Mi/Peer intercambiados; solo uno acaba en un plan que hace
// enqueue, el otro cae en un plan "me toca descartar".
//
// (1) Cola más corta gana
+!route_symmetric(CId, W, H, Weight, Tags, MyL, _, PeerL, _) :
        MyL < PeerL <-
    .print("  Mi cola menor (", MyL, " < ", PeerL, ") → me quedo ", CId);
    !enqueue(CId, W, H, Weight, Tags).

+!route_symmetric(CId, _, _, _, _, MyL, _, PeerL, _) :
        MyL > PeerL <-
    .print("  Peer cola menor (", PeerL, " < ", MyL, ") — descarto ", CId).

// (2) Empate de cola — el no-ocupado gana sobre el ocupado
+!route_symmetric(CId, W, H, Weight, Tags, L, MyS, L, busy) :
        MyS \== busy <-
    .print("  Empate cola, peer ocupado y yo no → me quedo ", CId);
    !enqueue(CId, W, H, Weight, Tags).

+!route_symmetric(CId, _, _, _, _, L, busy, L, PeerS) :
        PeerS \== busy <-
    .print("  Empate cola, yo ocupado y peer no — descarto ", CId).

// (3) Empate de cola y ambos no-ocupados — idle (en zona) gana sobre
//     going_idle (yendo a zona)
+!route_symmetric(CId, W, H, Weight, Tags, L, idle, L, going_idle) <-
    .print("  Empate cola, yo en zona idle vs peer going_idle → me quedo ", CId);
    !enqueue(CId, W, H, Weight, Tags).

+!route_symmetric(CId, _, _, _, _, L, going_idle, L, idle) <-
    .print("  Empate cola, peer en zona idle vs yo going_idle — descarto ", CId).

// (4) Empate absoluto (misma cola y mismo estado) — robot_heavy gana
+!route_symmetric(CId, W, H, Weight, Tags, L, S, L, S) :
        .my_name(robot_heavy) <-
    .print("  Empate absoluto — robot_heavy gana → me quedo ", CId);
    !enqueue(CId, W, H, Weight, Tags).

+!route_symmetric(CId, _, _, _, _, _, _, _, _) <-
    .print("  Empate absoluto — robot_heavy se queda con ", CId, ", yo descarto").
