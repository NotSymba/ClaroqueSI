// ═════════════════════════════════════════════════════════════
// WORK.ASL  —  lógica común de trabajo para los robots
//
// Cada robot mantiene creencias locales sobre la topología de
// estanterías y decide por sí mismo a cuál acudir (no depende
// de una asignación explícita del scheduler).
//
// Flujo de un contenedor:
//   1. Scheduler → container_available(CId, W, H, Weight, Type)
//   2. Robot decide si puede (can_i_manage) y lo encola.
//   3. Al procesarlo, pregunta al scheduler la ubicación actual
//      (provide_location → container_location) y va a recogerlo.
//   4. Elige LOCALMENTE la estantería más cercana compatible con
//      el tipo y que no esté en la lista negra. Si drop_at falla,
//      la añade a la lista negra y prueba otra.
//   5. Al acabar notifica `guardado` al scheduler.
//
// Ciclo de salida (exit_item + claim):
//   El scheduler publica a todos los robots exit_item(CId, Loc,
//   W, V, Type, Kind) durante un deadline. Cada robot escoge
//   autónomamente el más cercano que pueda cargar y pide claim
//   al scheduler antes de retirarlo. Al conceder, ejecuta la
//   salida (retrieve desde shelf o pickup desde entrada) y
//   deposita en una celda libre de la zona de salida.
// ═════════════════════════════════════════════════════════════
 

state(idle).
container_queue([]).

// ─────────────────────────────────────────────────────────────
//  CREENCIAS LOCALES: TOPOLOGÍA DE ESTANTERÍAS
//  Cada robot conoce dónde están y qué tipo admite cada una.
// ─────────────────────────────────────────────────────────────
shelf_location(shelf_1, 10,  2).
shelf_location(shelf_2, 12,  2).
shelf_location(shelf_3, 14,  2).
shelf_location(shelf_4, 16,  2).
shelf_location(shelf_5, 10,  6).
shelf_location(shelf_6, 13,  6).
shelf_location(shelf_7, 16,  6).
shelf_location(shelf_8, 10, 10).
shelf_location(shelf_9, 14, 10).

// Clasificación del paquete: "regular" = standard ó fragile (comparten shelves);
// los urgent van por su propio canal. Si aparece un tipo nuevo basta con añadir
// un hecho regular_container/1 y funcionará todo (accepts, pick_shelf, …).
regular_container(standard).
regular_container(fragile).

// Clasificación de las shelves:
urgent_shelf(shelf_1).  urgent_shelf(shelf_5).  urgent_shelf(shelf_8).
regular_shelf(shelf_2). regular_shelf(shelf_3). regular_shelf(shelf_4).
regular_shelf(shelf_6). regular_shelf(shelf_7). regular_shelf(shelf_9).

// Regla de aceptación: una shelf admite un paquete si ambos son del mismo
// "canal" (urgent ↔ urgent_shelf, regular ↔ regular_shelf).
accepts(urgent, S) :- urgent_shelf(S).
accepts(Type,   S) :- regular_container(Type) & regular_shelf(S).

// Celdas libres de la zona de salida (todas inicialmente).
exit_cell(0,0). exit_cell(0,1). exit_cell(1,0). exit_cell(1,1).
exit_cell(2,0). exit_cell(2,1).

// ─────────────────────────────────────────────────────────────
//  ESTADO COMPARTIDO DE ESTANTERÍAS (peer-to-peer, opción A)
//
//  Cada robot lleva su propia copia del estado de las estanterías:
//    · shelf_capacity(Shelf, MaxW, MaxV)         — estático
//    · shelf_usage_local(Shelf, CurW, CurV)      — depósitos confirmados
//    · shelf_reservation(Shelf, Owner, W, V, CId) — pre-reservas activas
//      de CUALQUIER robot (incluido él mismo), para paquetes en vuelo
//
//  Protocolo entre robots (peer_broadcast):
//    · shelf_reserve(CId, Shelf, W, V)   antes del pickup
//    · shelf_commit(CId, Shelf, W, V)    al hacer drop_at con éxito
//    · shelf_release(CId, Shelf, W, V)   si el drop falló (blacklist)
//    · shelf_retrieved(CId, Shelf, W, V) al retrieve en el ciclo de salida
//
//  La elección es LOCAL siguiendo robot_shelf_priority (urgentes por
//  distancia). Se acepta la primera shelf donde usage+reservas+paquete
//  cabe. Si ninguna cabe → el paquete se marca unstorable y NO se recoge.
// ─────────────────────────────────────────────────────────────
shelf_capacity(shelf_1, 50,  8).
shelf_capacity(shelf_2, 50,  8).
shelf_capacity(shelf_3, 50,  8).
shelf_capacity(shelf_4, 50,  8).
shelf_capacity(shelf_5, 100, 12).
shelf_capacity(shelf_6, 100, 12).
shelf_capacity(shelf_7, 100, 12).
shelf_capacity(shelf_8, 200, 20).
shelf_capacity(shelf_9, 200, 20).

shelf_usage_local(shelf_1, 0, 0). shelf_usage_local(shelf_2, 0, 0).
shelf_usage_local(shelf_3, 0, 0). shelf_usage_local(shelf_4, 0, 0).
shelf_usage_local(shelf_5, 0, 0). shelf_usage_local(shelf_6, 0, 0).
shelf_usage_local(shelf_7, 0, 0). shelf_usage_local(shelf_8, 0, 0).
shelf_usage_local(shelf_9, 0, 0).
// ─────────────────────────────────────────────────────────────
//  ANUNCIO DE CONTENEDOR DISPONIBLE (desde scheduler)
//  robot_heavy define is_router_robot y sobreescribe este plan con
//  su propia lógica de coordinación con heavy2.
//
//  Durante exit_in_progress el robot TAMBIÉN encola los nuevos; lo que
//  no hace es *procesarlos* hasta que el ciclo de salida haya terminado
//  para él (ver guards de check_idle/process_next).
// ─────────────────────────────────────────────────────────────
+container_available(CId, W, H, Weight, Type) :
        can_i_manage(W, H, Weight) & not is_router_robot <-
    !enqueue(CId, W, H, Weight, Type);
    .abolish(container_available(CId, _, _, _, _)).

+container_available(CId, W, H, Weight, Type) : not is_router_robot <-
    .abolish(container_available(CId, _, _, _, _)).

// ─────────────────────────────────────────────────────────────
//  COORDINACIÓN SIMÉTRICA HEAVY ↔ HEAVY2 (ambos is_router_robot)
//
//  El scheduler anuncia container_available a AMBOS heavy. Cada uno
//  consulta al peer su estado y aplica la MISMA regla determinista:
//    1) menos paquetes actualmente almacenados (my_stored) → gana
//    2) empate: menor cola → gana
//    3) empate: idle > going_idle > busy
//    4) empate absoluto: robot_heavy gana (desempate por nombre)
//  El perdedor simplemente descarta — no envía assign_here. Así un solo
//  robot encola cada paquete, sin solapamientos ni mensajes extra.
//
//  Si el peer no responde en 2s (caso degenerado) nos lo quedamos para
//  no perder el paquete.
// ─────────────────────────────────────────────────────────────
+container_available(CId, W, H, Weight, Type) :
        is_router_robot & can_i_manage(W, H, Weight) <-
    !decide_heavy_peer(CId, W, H, Weight, Type);
    .abolish(container_available(CId, _, _, _, _)).

+container_available(CId, _, _, _, _) : is_router_robot <-
    .abolish(container_available(CId, _, _, _, _)).

+!decide_heavy_peer(CId, W, H, Weight, Type) :
        container_queue(MyQ) & state(MyS) <-
    .length(MyQ, MyL);
    .findall(s(C, Sh), my_stored(C, Sh, _, _), SL);
    .length(SL, MyN);
    !heavy_peer_name(PeerName);
    .my_name(Me);
    .abolish(heavy_peer_info(_, _, _));
    .print("decide_heavy_peer ", CId, " — mis stored=", MyN, ", cola=", MyL, ", estado=", MyS);
    .send(PeerName, achieve, report_heavy_info(Me));
    .wait({+heavy_peer_info(_, _, _)}, 2000, _);
    if (heavy_peer_info(PeerN, PeerL, PeerS)) {
        .abolish(heavy_peer_info(_, _, _));
        .print("Peer ", PeerName, ": stored=", PeerN, ", cola=", PeerL, ", estado=", PeerS);
        !route_symmetric(CId, W, H, Weight, Type, MyN, MyL, MyS, PeerN, PeerL, PeerS)
    } else {
        .print("Peer ", PeerName, " no responde — me quedo ", CId);
        !enqueue(CId, W, H, Weight, Type)
    }.

+!heavy_peer_name(robot_heavy2) : .my_name(robot_heavy).
+!heavy_peer_name(robot_heavy)  : .my_name(robot_heavy2).

+!report_heavy_info(Requester) :
        container_queue(Q) & state(S) <-
    .length(Q, L);
    .findall(s(C, Sh), my_stored(C, Sh, _, _), SL);
    .length(SL, N);
    .send(Requester, tell, heavy_peer_info(N, L, S)).

// Regla simétrica. Los dos heavy ejecutan esta misma cadena con los
// valores Mi/Peer intercambiados; solo uno acaba en un plan que hace
// enqueue, el otro cae en un plan "me toca descartar".
//
// (1) Menos almacenado gana
+!route_symmetric(CId, W, H, Weight, Type, MyN, _, _, PeerN, _, _) :
        MyN < PeerN <-
    .print("  Yo tengo menos almacenado (", MyN, " < ", PeerN, ") → me quedo ", CId);
    !enqueue(CId, W, H, Weight, Type).

+!route_symmetric(CId, _, _, _, _, MyN, _, _, PeerN, _, _) :
        MyN > PeerN <-
    .print("  Peer tiene menos almacenado (", PeerN, " < ", MyN, ") — descarto ", CId).

// (2) Empate almacenado — menos cola gana
+!route_symmetric(CId, W, H, Weight, Type, N, MyL, _, N, PeerL, _) :
        MyL < PeerL <-
    .print("  Empate stored, mi cola menor (", MyL, " < ", PeerL, ") → me quedo ", CId);
    !enqueue(CId, W, H, Weight, Type).

+!route_symmetric(CId, _, _, _, _, N, MyL, _, N, PeerL, _) :
        MyL > PeerL <-
    .print("  Empate stored, peer cola menor — descarto ", CId).

// (3) Empate N y L — idle gana sobre lo que no es idle
+!route_symmetric(CId, W, H, Weight, Type, N, L, idle, N, L, PeerS) :
        PeerS \== idle <-
    .print("  Empate N+L, yo idle → me quedo ", CId);
    !enqueue(CId, W, H, Weight, Type).

+!route_symmetric(CId, _, _, _, _, N, L, MyS, N, L, idle) :
        MyS \== idle <-
    .print("  Empate N+L, peer idle — descarto ", CId).

// (4) Empate N, L, ninguno idle — going_idle gana sobre busy
+!route_symmetric(CId, W, H, Weight, Type, N, L, going_idle, N, L, busy) <-
    .print("  Empate, yo going_idle vs peer busy → me quedo ", CId);
    !enqueue(CId, W, H, Weight, Type).

+!route_symmetric(CId, _, _, _, _, N, L, busy, N, L, going_idle) <-
    .print("  Empate, peer going_idle — descarto ", CId).

// (5) Empate absoluto (misma N, L, S) — robot_heavy gana por nombre
+!route_symmetric(CId, W, H, Weight, Type, N, L, S, N, L, S) :
        .my_name(robot_heavy) <-
    .print("  Empate absoluto — robot_heavy gana → me quedo ", CId);
    !enqueue(CId, W, H, Weight, Type).

+!route_symmetric(CId, _, _, _, _, _, _, _, _, _, _) <-
    .print("  Empate absoluto — robot_heavy se queda con ", CId, ", yo descarto").

// ─────────────────────────────────────────────────────────────
//  COLA DE CONTENEDORES
// ─────────────────────────────────────────────────────────────
+!enqueue(CId, W, H, Weight, urgent) : container_queue(Q) <-
    -container_queue(_);
    +container_queue([pkg(CId, Weight, W, H, urgent) | Q]);
    .print("Encolado urgente: ", CId);
    !check_idle.

+!enqueue(CId, W, H, Weight, Type) : container_queue(Q) <-
    .concat(Q, [pkg(CId, Weight, W, H, Type)], NewQ);
    -container_queue(_);
    +container_queue(NewQ);
    .print("Encolado: ", CId);
    !check_idle.

// Si estoy en plena salida, encolo pero no avanzo cola: se reanudará
// al terminar el exit en curso (ver execute_exit).
+!check_idle : exit_in_progress(_) <- true.
+!check_idle : state(idle) <- !process_next.
+!check_idle : state(going_idle) <-
    .drop_intention(go_idle);
    -+state(idle);
    !process_next.
+!check_idle <- true.

// ─────────────────────────────────────────────────────────────
//  PROCESAR COLA
//  Prioridad: 1) exit_item del deadline activo (autónomo, vía claim)
//             2) cola normal de contenedores
//             3) ir a idle
// ─────────────────────────────────────────────────────────────
+!process_next : exit_in_progress(_) <- true.

+!process_next :
    state(idle) &
    exit_item(_, _, _, _, _, _) <-
    !try_exit_or_fallback.

+!process_next : container_queue([]) <- !go_idle.

+!process_next :
    container_queue([pkg(CId, Weight, W, H, Type) | Rest]) &
    state(idle) <-
    -+container_queue(Rest);
    -state(idle);
    +state(busy);
    !handle_container(CId, Weight, W, H, Type).

// ─────────────────────────────────────────────────────────────
//  GESTIÓN DE UN CONTENEDOR
//
//  La elección de estantería la hace el propio robot mirando SU copia del
//  estado (usage + reservas de todos los robots). Si nada cabe → unstorable
//  SIN recogerlo. Si encuentra shelf → pre-reserva, broadcast, pickup, drop.
// ─────────────────────────────────────────────────────────────
+!handle_container(CId, Weight, W, H, Type) <-
    !query_location(CId, CX, CY);
    if (CX == none) {
        .print("Sin ubicación para ", CId, ", descarto tarea");
        -+state(idle);
        !process_next
    } else {
        V = W * H;
        !choose_shelf_local(CId, Type, Weight, V, Chosen);
        if (Chosen == none) {
            .print("Sin shelf con hueco (incluyendo reservas) para ", CId, " (", Type, ") — unstorable");
            .send(scheduler, tell, unstorable(CId, Type));
            -+state(idle);
            !process_next
        } else {
            !reserve_shelf(CId, Chosen, Weight, V);
            !goto_pos(CId, CX, CY);
            pickup(CId);
            !navigate_to_shelf(Chosen);
            // try_drop llamará a finish_task internamente con la shelf que
            // ACEPTÓ el drop (original o alternativa tras blacklisting).
            // Si llamáramos !finish_task aquí con `Chosen`, romperíamos en
            // los casos en que try_drop cayó en una alternativa.
            !try_drop(CId, Weight, W, H, Type, Chosen)
        }
    }.

// ─────────────────────────────────────────────────────────────
//  SELECCIÓN LOCAL DE ESTANTERÍA (usa shelf_usage_local + reservas)
//
//  Urgentes → urgent shelves ordenadas por distancia Manhattan.
//  Regulares → robot_shelf_priority del robot, filtrada por regular_shelf.
//  Blacklist local se aplica siempre (shelves que fallaron el drop).
// ─────────────────────────────────────────────────────────────
+!choose_shelf_local(_, urgent, Weight, V, Shelf) <-
    .my_name(Me);
    see;
    !robot_position(RX, RY);
    .findall(sd(S, D),
             (urgent_shelf(S) & not shelf_blacklist(S) &
              shelf_location(S, SX, SY) &
              D = math.abs(SX - RX) + math.abs(SY - RY)),
             Raw);
    !sort_sd(Raw, Sorted);
    !project_sd(Sorted, Ordered);
    !first_fitting(Ordered, Weight, V, Shelf).

+!choose_shelf_local(_, Type, Weight, V, Shelf) :
        regular_container(Type) & robot_shelf_priority(Prio) <-
    !filter_regular_not_blacklisted(Prio, Filtered);
    !first_fitting(Filtered, Weight, V, Shelf).

// Catch-all: tipo desconocido o cualquier guarda no satisfecha → unstorable.
+!choose_shelf_local(CId, Type, _, _, none) <-
    .print("AVISO: choose_shelf_local sin plan aplicable para ", CId, "/", Type).

// Lectura segura de la posición. Evita que un ?at/3 ausente tumbe la intención.
+!robot_position(X, Y) : .my_name(Me) & at(Me, X, Y).
+!robot_position(X, Y) : idlezone(X, Y) <-
    .print("AVISO: at/3 no disponible — uso idlezone(", X, ",", Y, ") como referencia").

+!filter_regular_not_blacklisted([], []).
+!filter_regular_not_blacklisted([S | T], [S | Rest]) :
        regular_shelf(S) & not shelf_blacklist(S) <-
    !filter_regular_not_blacklisted(T, Rest).
+!filter_regular_not_blacklisted([_ | T], Rest) <-
    !filter_regular_not_blacklisted(T, Rest).

// Caso base: lista vacía → no hay shelf válida.
+!first_fitting([], _, _, none).

// Caso recursivo: probamos el primero, decidimos en plan auxiliar
// (split en cláusulas para evitar sorpresas con .if_then_else cuando
// alguna sub-meta no termina ground).
+!first_fitting([S | Rest], W, V, Chosen) <-
    !shelf_fits(S, W, V, Fits);
    !first_fitting_pick(Fits, S, Rest, W, V, Chosen).

// Si encajó, devuelve esta shelf por el head.
+!first_fitting_pick(true, S, _, _, _, S).
// Cualquier otro Fits (false / unbound / lo que sea) → siguiente candidata.
+!first_fitting_pick(_, _, Rest, W, V, Chosen) <-
    !first_fitting(Rest, W, V, Chosen).

+!shelf_fits(S, W, V, R) :
        shelf_capacity(S, MaxW, MaxV) & shelf_usage_local(S, UW, UV) <-
    .findall(rv(RW, RV), shelf_reservation(S, _, RW, RV, _), L);
    !sum_rv(L, 0, 0, TW, TV);
    if (UW + TW + W <= MaxW & UV + TV + V <= MaxV) {
        R = true
    } else {
        R = false
    }.

// Catch-all defensivo: si por una race entre commit/release falta
// shelf_capacity o shelf_usage_local para esta shelf, devolvemos false
// en lugar de dejar morir la intención sin plan aplicable.
+!shelf_fits(S, _, _, false) <-
    .print("AVISO: shelf_fits sin datos para ", S, " — devuelvo false").

+!sum_rv([], AW, AV, AW, AV).
+!sum_rv([rv(W, V) | Rest], AW, AV, TW, TV) <-
    !sum_rv(Rest, AW + W, AV + V, TW, TV).

+!sort_sd([], []).
+!sort_sd(L, [sd(BS, BD) | Rest]) <-
    !min_sd(L, sd(none, 99999), sd(BS, BD));
    .delete(sd(BS, BD), L, Without);
    !sort_sd(Without, Rest).

+!min_sd([], Cur, Cur).
+!min_sd([sd(S, D) | R], sd(_, CD), Best) : D < CD <-
    !min_sd(R, sd(S, D), Best).
+!min_sd([_ | R], Cur, Best) <-
    !min_sd(R, Cur, Best).

+!project_sd([], []).
+!project_sd([sd(S, _) | R], [S | Out]) <-
    !project_sd(R, Out).

// ─────────────────────────────────────────────────────────────
//  PROTOCOLO DE RESERVAS (peer-to-peer)
// ─────────────────────────────────────────────────────────────
+!reserve_shelf(CId, Shelf, W, V) <-
    .my_name(Me);
    +shelf_reservation(Shelf, Me, W, V, CId);
    .print("Reservo ", Shelf, " para ", CId, " (w=", W, ", v=", V, ")");
    !peer_broadcast(shelf_reserve(CId, Shelf, W, V)).

+!release_shelf(CId, Shelf, W, V) <-
    .my_name(Me);
    -shelf_reservation(Shelf, Me, W, V, CId);
    .print("Libero reserva ", Shelf, " de ", CId);
    !peer_broadcast(shelf_release(CId, Shelf, W, V)).

// IMPORTANTE: usamos .abolish + + en lugar de -+. El operador -+ con
// argumentos calculados (UW + W) intenta borrar por unificación contra el
// literal con esos VALORES NUEVOS, no contra el viejo — y deja duplicados.
// Con .abolish(shelf_usage_local(Shelf, _, _)) eliminamos cualquier copia
// existente para esa shelf antes de añadir la nueva.
//
// [atomic] evita que dos handlers concurrentes (commit + retrieved, o dos
// commits llegando casi a la vez) lean el mismo UW antiguo y se pisen.
@local_commit[atomic]
+!commit_shelf(CId, Shelf, W, V) <-
    .my_name(Me);
    -shelf_reservation(Shelf, Me, W, V, CId);
    !update_usage_local(Shelf, W, V);
    !peer_broadcast(shelf_commit(CId, Shelf, W, V)).

@local_retrieved[atomic]
+!retrieved_shelf(CId, Shelf, W, V) <-
    !update_usage_local(Shelf, -W, -V);
    !peer_broadcast(shelf_retrieved(CId, Shelf, W, V)).

// Helper común: lee usage actual, suma deltas (positivos = commit,
// negativos = retrieve), clampa a 0 y reescribe limpio.
+!update_usage_local(Shelf, DW, DV) :
        shelf_usage_local(Shelf, UW, UV) <-
    NewWraw = UW + DW;
    NewVraw = UV + DV;
    if (NewWraw < 0) { NewW = 0 } else { NewW = NewWraw };
    if (NewVraw < 0) { NewV = 0 } else { NewV = NewVraw };
    .abolish(shelf_usage_local(Shelf, _, _));
    +shelf_usage_local(Shelf, NewW, NewV).

// Si por una desincronía pasada no hay creencia previa, partimos de 0.
+!update_usage_local(Shelf, DW, DV) <-
    .print("AVISO: shelf_usage_local(", Shelf, ",_,_) inexistente, parto de 0");
    if (DW < 0) { NewW = 0 } else { NewW = DW };
    if (DV < 0) { NewV = 0 } else { NewV = DV };
    .abolish(shelf_usage_local(Shelf, _, _));
    +shelf_usage_local(Shelf, NewW, NewV).

+!peer_broadcast(Msg) <-
    .my_name(Me);
    !peer_send(robot_light, Me, Msg);
    !peer_send(robot_medium, Me, Msg);
    !peer_send(robot_heavy, Me, Msg);
    !peer_send(robot_heavy2, Me, Msg).

+!peer_send(Me, Me, _).
+!peer_send(Other, _, Msg) <-
    .send(Other, tell, Msg).

// ─────────────────────────────────────────────────────────────
//  HANDLERS DE MENSAJES ENTRANTES (otros robots)
// ─────────────────────────────────────────────────────────────
+shelf_reserve(CId, Shelf, W, V)[source(R)] <-
    +shelf_reservation(Shelf, R, W, V, CId);
    -shelf_reserve(CId, Shelf, W, V)[source(R)].

@peer_commit[atomic]
+shelf_commit(CId, Shelf, W, V)[source(R)] <-
    -shelf_reservation(Shelf, R, W, V, CId);
    !update_usage_local(Shelf, W, V);
    -shelf_commit(CId, Shelf, W, V)[source(R)].

+shelf_release(CId, Shelf, W, V)[source(R)] <-
    -shelf_reservation(Shelf, R, W, V, CId);
    -shelf_release(CId, Shelf, W, V)[source(R)].

@peer_retrieved[atomic]
+shelf_retrieved(CId, Shelf, W, V)[source(R)] <-
    !update_usage_local(Shelf, -W, -V);
    -shelf_retrieved(CId, Shelf, W, V)[source(R)].

// ─────────────────────────────────────────────────────────────
//  CONSULTA DE UBICACIÓN AL SCHEDULER
//  Protocolo: robot → scheduler (achieve provide_location(CId,Me))
//             scheduler → robot (tell container_location(CId,X,Y))
// ─────────────────────────────────────────────────────────────
+!query_location(CId, X, Y) <-
    .abolish(container_location(CId, _, _));
    .my_name(Me);
    .send(scheduler, achieve, provide_location(CId, Me));
    .wait({+container_location(CId, _, _)}, 3000, _);
    if (container_location(CId, RX, RY)) {
        X = RX; Y = RY;
        .abolish(container_location(CId, _, _));
    } else {
        .print("Timeout esperando container_location de ", CId);
        X = none; Y = none
    }.

// goto_pos actualiza nuestro belief local y navega hasta quedar adyacente
+!goto_pos(CId, TX, TY) <-
    -container_relocated(CId, _, _);
    .print("Voy a recoger ", CId, " en (", TX, ",", TY, ")");
    !clear_nav_state;
    !navigate_adjacent(TX, TY);
    !verify_position(CId, TX, TY).

+!verify_position(CId, TX, TY) <-
    !query_location(CId, NX, NY);
    if (NX == none) {
        .print("Confirmación ", CId, " falló — el contenedor ya no existe, abandono");
        .fail
    } else {
        if (NX == TX & NY == TY) {
            .print("Contenedor ", CId, " confirmado en (", TX, ",", TY, ")")
        } else {
            .print("Contenedor ", CId, " reubicado a (", NX, ",", NY, "). Re-navegando...");
            !clear_nav_state;
            !navigate_adjacent(NX, NY);
            !verify_position(CId, NX, NY)
        }
    }.

// ─────────────────────────────────────────────────────────────
//  DEPOSITAR
//
//  Si drop_at falla, liberamos la reserva (broadcast release), añadimos
//  la shelf a la blacklist local e intentamos elegir otra. Si no queda
//  ninguna que acepte + tenga hueco, caso límite: entregamos el paquete
//  directamente a la zona de salida y pedimos al scheduler que dispare
//  un ciclo de salida del grupo para vaciar las estanterías.
// ─────────────────────────────────────────────────────────────
+!try_drop(CId, Weight, W, H, Type, Shelf) <-
    drop_at(Shelf);
    .print("Depositado ", CId, " en ", Shelf);
    // Cierre de la cadena: finish_task usa SIEMPRE la shelf real donde se
    // aceptó el drop. Si veníamos de una recursión por blacklist, Shelf es
    // ya la alternativa y la reserva activa coincide.
    !finish_task(CId, Shelf).

-!try_drop(CId, Weight, W, H, Type, Shelf) <-
    .print("Fallo al depositar ", CId, " en ", Shelf, ", libero reserva y pruebo otra...");
    V = W * H;
    !release_shelf(CId, Shelf, Weight, V);
    +shelf_blacklist(Shelf);
    !choose_shelf_local(CId, Type, Weight, V, Alt);
    if (Alt == none) {
        .wait(2000);
        !choose_shelf_local(CId, Type, Weight, V, Retry);
        if (Retry == none) {
            .print("Sigo sin alternativa para ", CId, " — caso límite: salida directa + ciclo de salida");
            !force_exit_carried(CId, Type);
            -+state(idle);
            !process_next
        } else {
            !reserve_shelf(CId, Retry, Weight, V);
            !navigate_to_shelf(Retry);
            !try_drop(CId, Weight, W, H, Type, Retry)
        }
    } else {
        !reserve_shelf(CId, Alt, Weight, V);
        !navigate_to_shelf(Alt);
        !try_drop(CId, Weight, W, H, Type, Alt)
    }.

// ─────────────────────────────────────────────────────────────
//  FINALIZAR TAREA → commit de la reserva + notificación al scheduler
// ─────────────────────────────────────────────────────────────
// Caso límite: el robot lleva un paquete que ya no puede colocar en
// ninguna shelf (típicamente por desajuste de sincronización o
// precisión en la contabilidad). Lo entregamos directamente en la
// zona de salida y pedimos al scheduler que arranque un ciclo de
// salida del grupo correspondiente para vaciar las estanterías.
+!force_exit_carried(CId, Type) <-
    !go_to_exit_cell(EX, EY);
    drop_at_exit(EX, EY);
    .send(scheduler, tell, force_exit_cycle(Type));
    .print("Caso límite: ", CId, " entregado a la salida y ciclo solicitado (tipo=", Type, ").").

// Caso normal: la reserva sigue ahí (no hubo purga por deadline en medio).
+!finish_task(CId, Shelf) :
        .my_name(Me) & shelf_reservation(Shelf, Me, W, V, CId) <-
    task_complete(CId, Shelf);
    !commit_shelf(CId, Shelf, W, V);
    .send(scheduler, tell, guardado(CId, Shelf));
    +my_stored(CId, Shelf, W, V);
    .abolish(shelf_blacklist(_));
    -+state(idle);
    .print("Completado: ", CId, " → ", Shelf);
    !process_next.

// Reserva desaparecida (típicamente purgada al arrancar un deadline sobre
// esta shelf justo mientras estábamos de viaje). El drop ya se realizó,
// así que notificamos guardado al scheduler pero NO hacemos commit_shelf
// (no tenemos W,V fiables aquí y el supervisor es la fuente autoritativa).
+!finish_task(CId, Shelf) <-
    .print("AVISO: finish_task sin shelf_reservation para ", CId, " en ", Shelf,
           " — probable purga por deadline; envío guardado sin commit local");
    task_complete(CId, Shelf);
    .send(scheduler, tell, guardado(CId, Shelf));
    .abolish(shelf_blacklist(_));
    -+state(idle);
    !process_next.

// ─────────────────────────────────────────────────────────────
//  IR A IDLE ZONE cuando no hay trabajo
// ─────────────────────────────────────────────────────────────
+!go_idle : idlezone(IX, IY) <-
    -+state(going_idle);
    .print("Sin trabajo, volviendo a idle zone (", IX, ",", IY, ")");
    !clear_nav_state;
    !navigate_to(IX, IY);
    -+state(idle);
    .print("En idle zone, esperando trabajo...").

-!go_idle <-
    .print("No pude llegar a idle zone, esperando trabajo aquí");
    -+state(idle).

// ═════════════════════════════════════════════════════════════
//  CONTENEDOR DESTRUIDO (splash) — purga local de referencias
//
//  El env emite container_destroyed/2 a todos los agentes cuando
//  un robot pisa un paquete sin recoger. Cada robot debe:
//    · sacar el CId de su cola si lo tenía pendiente
//    · borrar exit_item / container_available / location asociados
//    · liberar la reserva de shelf si la hizo (broadcast a peers)
//    · borrar my_stored si por algún motivo lo tenía registrado
//
//  No tocamos picked(_) porque el env nunca destruye paquetes recogidos
//  (escacharPaquete excluye c.isPicked()), así que un container_destroyed
//  no puede coincidir con un paquete que llevamos en la mano.
// ═════════════════════════════════════════════════════════════
+container_destroyed(CId, _) <-
    .print("Aviso: ", CId, " destruido — limpio referencias locales");
    !remove_from_queue(CId);
    .abolish(container_available(CId, _, _, _, _));
    .abolish(exit_item(CId, _, _, _, _, _));
    .abolish(container_location(CId, _, _));
    .abolish(container_relocated(CId, _, _));
    .abolish(location(CId, _, _));
    .abolish(my_stored(CId, _, _, _));
    !release_if_reserved(CId);
    -container_destroyed(CId, _).

+!remove_from_queue(CId) : container_queue(Q) <-
    !filter_queue(Q, CId, NewQ);
    -+container_queue(NewQ).
+!remove_from_queue(_).

+!filter_queue([], _, []).
+!filter_queue([pkg(CId, _, _, _, _) | Rest], CId, Out) <-
    !filter_queue(Rest, CId, Out).
+!filter_queue([Pkg | Rest], CId, [Pkg | Out]) <-
    !filter_queue(Rest, CId, Out).

// Si tenía una reserva activa para este CId la libero (broadcast a peers).
+!release_if_reserved(CId) :
        .my_name(Me) & shelf_reservation(Shelf, Me, W, V, CId) <-
    !release_shelf(CId, Shelf, W, V).
+!release_if_reserved(_).

// ═════════════════════════════════════════════════════════════
//  RECUPERACIÓN: tengo un paquete en la mano y la tarea actual
//  ha fallado. Best-effort: lo llevo a la zona de salida y allí
//  lo dejo. El env notifica container_exited al scheduler/supervisor
//  automáticamente. Si recover_carrying falla, sólo se loguea: el
//  paquete podría seguir en la mano, pero al menos no propagamos
//  el fallo y los siguientes ciclos pueden continuar.
// ═════════════════════════════════════════════════════════════
+!recover_carrying : picked(CId) <-
    .print("Recuperación: tengo ", CId, " en la mano — lo entrego en la salida");
    !clear_nav_state;
    !go_to_exit_cell(EX, EY);
    drop_at_exit(EX, EY);
    .print("Recuperación: ", CId, " entregado en la salida").
+!recover_carrying.

-!recover_carrying <-
    .print("AVISO: recuperación de paquete en mano no completó (puede quedar carrying)").

// ═════════════════════════════════════════════════════════════
//  FALLOS DE handle_container — limpieza segura
//
//  Cubre: pickup fallido (already_carrying / invalid_pick / too_far),
//  navigate_to_shelf sin candidatas, query_location timeout, splash
//  del propio contenedor objetivo, etc. Liberamos la reserva activa
//  (si la tenemos), entregamos en la salida lo que llevemos en mano
//  y volvemos a procesar la cola para no quedar bloqueados.
// ═════════════════════════════════════════════════════════════
-!handle_container(CId, _, _, _, _) <-
    .print("AVISO: handle_container(", CId, ") falló — recupero estado");
    !release_if_reserved(CId);
    !recover_carrying;
    .abolish(shelf_blacklist(_));
    -+state(idle);
    !process_next.

// ═════════════════════════════════════════════════════════════
//  CICLO DE SALIDA POR DEADLINES  (nuevo protocolo, autónomo)
//
//  El scheduler publica a los 4 robots:
//    tell exit_item(CId, Loc, W, V, Type, Kind)
//  donde Loc = at_shelf(S) | at_entry(X,Y) y Kind = short | long.
//
//  Los robots deciden autónomamente qué contenedor coger (el más
//  cercano que puedan cargar) y lo reclaman al scheduler:
//    achieve claim_exit(CId, Me)  →  claim_result(CId, granted|denied)
//
//  Al conceder, el scheduler broadcasts exit_taken(CId); los demás
//  robots abolishen su copia local. El que tiene granted ejecuta la
//  salida (retrieve desde shelf o pickup desde entrada + drop_at_exit)
//  y notifica al scheduler con tell exit_done(CId, Type).
// ═════════════════════════════════════════════════════════════

// Regla auxiliar: ¿puedo cargar este peso?
can_i_manage_weight(Weight) :-
    max_weight(MaxW) & Weight <= MaxW.

// Regla de autonomía: durante un deadline cada robot sólo se interesa por
//   · los paquetes que él mismo guardó (at_shelf + my_stored/4)
//   · los unstorable que quedaron en la entrada (at_entry, sin dueño)
// Así el scheduler no tiene que asignar nadie: cada robot filtra solo.
can_i_exit(CId, at_shelf(_))   :- my_stored(CId, _, _, _).
can_i_exit(_,   at_entry(_,_)).

// ─── Recepción de un exit_item ──────────────────────────────
// Si lo puedo cargar, intento avanzar. Si no, me quedo con la
// creencia por si el scheduler luego la retira vía exit_taken.
+exit_item(CId, _, W, _, Type, Kind)[source(scheduler)] :
        can_i_manage_weight(W) <-
    .print("Recibido exit_item ", CId, " (tipo ", Type, ", ", Kind, ")");
    !check_idle.

+exit_item(_, _, _, _, _, _)[source(scheduler)] <- true.

// El scheduler confirma que CId ya tiene dueño → lo descarto localmente
+exit_taken(CId)[source(scheduler)] <-
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_taken(CId)[source(scheduler)].

// Inicio/fin de deadline.
//
// Al ARRANCAR un deadline purgamos localmente todas las shelf_reservation
// cuyo shelf pertenezca al grupo que va a salir:
//   short → urgent_shelf   (S1, S5, S8)
//   long  → regular_shelf  (S2..S4, S6, S7, S9)
//
// Motivo: a veces quedan reservas huérfanas de operaciones abortadas
// (pickup fallido, navegación interrumpida, crash mid-flight...) que
// siguen contando como "pre-reserva" en shelf_fits y falsean el hueco
// disponible. El deadline es el momento natural para limpiar: los
// paquetes de ese tipo van a salir igualmente, así que cualquier reserva
// pendiente sobre esas shelves es basura.
+active_deadline(short)[source(scheduler)] <-
    .print("Robot: deadline short activo — purgo reservas en urgent shelves");
    !purge_reservations_urgent;
    !check_idle.

+active_deadline(long)[source(scheduler)] <-
    .print("Robot: deadline long activo — purgo reservas en regular shelves");
    !purge_reservations_regular;
    !check_idle.

-active_deadline(Kind)[source(scheduler)] <-
    .print("Robot: deadline ", Kind, " cerrado").

+!purge_reservations_urgent <-
    .findall(sr(S, O, W, V, CId),
             (shelf_reservation(S, O, W, V, CId) & urgent_shelf(S)),
             L);
    !drop_reservation_list(L).

+!purge_reservations_regular <-
    .findall(sr(S, O, W, V, CId),
             (shelf_reservation(S, O, W, V, CId) & regular_shelf(S)),
             L);
    !drop_reservation_list(L).

+!drop_reservation_list([]).
+!drop_reservation_list([sr(S, O, W, V, CId) | Rest]) <-
    .print("  purga shelf_reservation(", S, ",", O, ",", W, ",", V, ",", CId, ")");
    -shelf_reservation(S, O, W, V, CId);
    !drop_reservation_list(Rest).

// ─── Selección del mejor exit_item + lock atómico ───────────
//  Mejor = más cercano entre los que puedo cargar (Manhattan).
//
//  La elección + adquisición de lock (+exit_in_progress) + envío
//  del claim se hace dentro de un plan @atomic para que dos
//  eventos +exit_item concurrentes no hagan que este robot
//  arranque dos exits a la vez (era la causa del "teletransporte":
//  dos intenciones navegando al mismo tiempo hacia shelves distintas).
//
//  La respuesta del scheduler (claim_result) llega como EVENTO
//  (no con .wait) para que el robot no se quede bloqueado y para
//  que los cuatro robots progresen en paralelo.
@try_exit_atomic[atomic]
+!try_exit_or_fallback : not exit_in_progress(_) <-
    !pick_best_exit_item(Best);
    if (Best == none) {
        !fallback_to_normal
    } else {
        Best = ex(CId, Loc, _, _, Type, _);
        .print("Elijo exit_item ", CId, " (", Loc, "), pido claim");
        +exit_in_progress(CId);
        +pending_claim(CId, Loc, Type);
        -+state(busy);
        .drop_intention(go_idle);
        .my_name(Me);
        .abolish(claim_result(CId, _));
        .send(scheduler, achieve, claim_exit(CId, Me))
    }.

+!try_exit_or_fallback <- true.

+!fallback_to_normal : container_queue([]) <- !go_idle.
+!fallback_to_normal :
        container_queue([pkg(CId, Weight, W, H, Type) | Rest]) <-
    -+container_queue(Rest);
    -state(idle);
    +state(busy);
    !handle_container(CId, Weight, W, H, Type).

// Defensa en profundidad: SÓLO consideramos exit_items cuyo Kind coincide
// con un active_deadline(Kind) vigente. Si el scheduler cerró el deadline
// y todavía queda algún exit_item local por un untell tardío, lo ignoramos.
// Si no hay deadline activo, Cands = [] y caemos al fallback_to_normal.
+!pick_best_exit_item(Best) <-
    .my_name(Me);
    see;
    !robot_position(RX, RY);
    .findall(ex(CId, Loc, W, V, Type, Kind),
             (active_deadline(Kind) &
              exit_item(CId, Loc, W, V, Type, Kind) &
              can_i_manage_weight(W) &
              can_i_exit(CId, Loc)),
             Cands);
    !pick_closest_exit(Cands, RX, RY, none, 999999, Best).

+!pick_closest_exit([], _, _, Best, _, Best).
+!pick_closest_exit([ex(CId, Loc, W, V, Type, Kind) | Rest], RX, RY, Cur, MinD, Best) <-
    !dist_to_loc(Loc, RX, RY, D);
    if (D < MinD) {
        !pick_closest_exit(Rest, RX, RY, ex(CId, Loc, W, V, Type, Kind), D, Best)
    } else {
        !pick_closest_exit(Rest, RX, RY, Cur, MinD, Best)
    }.

+!dist_to_loc(at_shelf(S), RX, RY, D) :
        shelf_location(S, SX, SY) <-
    D = math.abs(SX - RX) + math.abs(SY - RY).
+!dist_to_loc(at_entry(X, Y), RX, RY, D) <-
    D = math.abs(X - RX) + math.abs(Y - RY).

// ─── Respuesta del claim (event-driven, no .wait) ───────────
//  Con pending_claim(CId, Loc, Type) guardamos los datos que
//  necesita execute_exit cuando finalmente llega la respuesta.
+claim_result(CId, granted)[source(scheduler)] :
        pending_claim(CId, Loc, Type) <-
    -claim_result(CId, granted)[source(scheduler)];
    -pending_claim(CId, Loc, Type);
    !execute_exit(CId, Loc, Type).

+claim_result(CId, denied)[source(scheduler)] :
        pending_claim(CId, _, _) <-
    .print("Claim denegado para ", CId, " — libero y reintento");
    -claim_result(CId, denied)[source(scheduler)];
    .abolish(pending_claim(CId, _, _));
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

// Cualquier claim_result stale: limpiamos y ya.
+claim_result(_, _)[source(scheduler)] <-
    .abolish(claim_result(_, _)[source(scheduler)]).

// ─────────────────────────────────────────────────────────────
//  EXIT CON GUARDAS DE DEADLINE
//
//  Antes de retrieve/pickup y antes de drop_at_exit comprobamos que
//  active_deadline(_) sigue vigente. Si el scheduler ya cerró el
//  deadline (untell active_deadline) NO podemos llevar el paquete
//  a salida — es exactamente el caso prohibido por el spec.
//
//  · Si el deadline expira ANTES del retrieve/pickup → abandono
//    limpio. El paquete se queda donde estaba (shelf o entrada) y
//    se intentará en el próximo deadline del mismo grupo.
//  · Si el deadline expira CON paquete en mano → re-almaceno en una
//    estantería compatible (puede ser la original u otra). El paquete
//    quedará disponible en el siguiente deadline del mismo grupo vía
//    stored_at del supervisor.
//
//  carrying_exit/5 marca "tengo paquete del ciclo de salida en la
//  mano" entre el retrieve/pickup y el drop_at_exit (o re-shelf).
// ─────────────────────────────────────────────────────────────
+!execute_exit(CId, at_shelf(Shelf), Type) <-
    .print("Exit de ", CId, " desde shelf ", Shelf);
    !navigate_to_shelf(Shelf);
    if (not active_deadline(_)) {
        .print("Deadline cerrado antes de retrieve de ", CId, " — abandono exit");
        !abort_exit_cleanup(CId)
    } else {
        retrieve(CId);
        ?my_stored(CId, Shelf, W, V);
        -my_stored(CId, Shelf, W, V);
        !retrieved_shelf(CId, Shelf, W, V);
        +carrying_exit(CId, Type, Shelf, W, V);
        !go_to_exit_cell(EX, EY);
        if (not active_deadline(_)) {
            .print("Deadline cerrado durante traslado a salida con ", CId, " — re-almaceno");
            !reshelf_carried(CId, Type, Shelf, W, V)
        } else {
            drop_at_exit(EX, EY);
            .abolish(carrying_exit(CId, _, _, _, _));
            .send(scheduler, tell, exit_done(CId, Type));
            .abolish(exit_item(CId, _, _, _, _, _));
            -exit_in_progress(_);
            -+state(idle);
            .print("Exit completo: ", CId);
            !process_next
        }
    }.

+!execute_exit(CId, at_entry(X, Y), Type) <-
    .print("Exit directo de ", CId, " desde entrada (", X, ",", Y, ")");
    !goto_pos(CId, X, Y);
    if (not active_deadline(_)) {
        .print("Deadline cerrado antes de pickup de ", CId, " — abandono exit");
        !abort_exit_cleanup(CId)
    } else {
        pickup(CId);
        !get_exit_dim(CId, EW, EV);
        +carrying_exit(CId, Type, none, EW, EV);
        !go_to_exit_cell(EX, EY);
        if (not active_deadline(_)) {
            .print("Deadline cerrado durante traslado a salida con ", CId, " — re-almaceno");
            !reshelf_carried(CId, Type, none, EW, EV)
        } else {
            drop_at_exit(EX, EY);
            .abolish(carrying_exit(CId, _, _, _, _));
            .send(scheduler, tell, exit_done(CId, Type));
            .abolish(exit_item(CId, _, _, _, _, _));
            -exit_in_progress(_);
            -+state(idle);
            .print("Exit directo completo: ", CId);
            !process_next
        }
    }.

-!execute_exit(CId, _, Type) <-
    .print("Fallo el exit de ", CId, " — recupero estado");
    // Si el fallo nos pilla con el paquete en la mano (típicamente
    // pickup ok pero navegación o drop_at_exit fallaron), best-effort
    // de entrega antes de cerrar; así no quedamos "carrying" para los
    // siguientes pickups (already_carrying).
    !recover_carrying;
    .abolish(carrying_exit(CId, _, _, _, _));
    .send(scheduler, tell, exit_done(CId, Type));
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

// ─────────────────────────────────────────────────────────────
//  ABANDONO LIMPIO (deadline expiró antes de retrieve/pickup)
//  El paquete se queda donde estaba: el siguiente deadline del
//  mismo grupo lo volverá a publicar (stored_at o unstorable_pending).
// ─────────────────────────────────────────────────────────────
+!abort_exit_cleanup(CId) <-
    .abolish(pending_claim(CId, _, _));
    .abolish(exit_item(CId, _, _, _, _, _));
    .abolish(carrying_exit(CId, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

// ─────────────────────────────────────────────────────────────
//  RE-ALMACENAMIENTO TRAS FIN DE DEADLINE (paquete en mano)
//
//  Reutilizamos choose_shelf_local para encontrar una estantería
//  compatible con el tipo (urgente o regular) y con hueco. La
//  shelf elegida puede ser la original (si todavía cabe, lo
//  natural) u otra. Tras el drop_at se hace commit + guardado al
//  scheduler como en el flujo de almacenamiento normal, dejando
//  my_stored para que el robot pueda retirarlo en el próximo
//  deadline del mismo grupo.
// ─────────────────────────────────────────────────────────────
+!reshelf_carried(CId, Type, _, W, V) <-
    !choose_shelf_local(CId, Type, W, V, Chosen);
    !reshelf_carried_dispatch(CId, Type, W, V, Chosen).

+!reshelf_carried_dispatch(CId, Type, _, _, none) <-
    .print("AVISO: sin shelf libre para re-almacenar ", CId, " — caso límite: salida directa + ciclo");
    !force_exit_carried(CId, Type);
    .abolish(carrying_exit(CId, _, _, _, _));
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

+!reshelf_carried_dispatch(CId, _, W, V, Shelf) <-
    !reserve_shelf(CId, Shelf, W, V);
    !navigate_to_shelf(Shelf);
    !try_reshelf_drop(CId, W, V, Shelf).

+!try_reshelf_drop(CId, W, V, Shelf) <-
    drop_at(Shelf);
    .print("Re-almacenado ", CId, " en ", Shelf, " (deadline expiró durante salida)");
    !commit_shelf(CId, Shelf, W, V);
    .send(scheduler, tell, guardado(CId, Shelf));
    +my_stored(CId, Shelf, W, V);
    .abolish(carrying_exit(CId, _, _, _, _));
    .abolish(exit_item(CId, _, _, _, _, _));
    .abolish(shelf_blacklist(_));
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

-!try_reshelf_drop(CId, W, V, Shelf) <-
    .print("Fallo re-almacenamiento ", CId, " en ", Shelf, " — pruebo otra");
    !release_shelf(CId, Shelf, W, V);
    +shelf_blacklist(Shelf);
    ?carrying_exit(CId, Type, OrigShelf, _, _);
    !reshelf_carried(CId, Type, OrigShelf, W, V).

// Lee W, V del exit_item local (todavía presente porque aún no lo
// hemos abolido). Si por alguna razón ya no está, devolvemos 0,0
// para que reshelf_carried elija una shelf que admita "cualquier"
// tamaño (las urgent shelves más pequeñas tienen 50/8, suficiente
// para la mayoría de paquetes pequeños/medianos).
+!get_exit_dim(CId, W, V) : exit_item(CId, _, EW, EV, _, _) <-
    W = EW; V = EV.
+!get_exit_dim(_, 0, 0).

// Elige una celda libre de la zona de salida y navega adyacente a ella.
// Reutiliza sort_by_distance de mov.asl (lista de pos(X,Y)).
+!go_to_exit_cell(X, Y) <-
    .findall(pos(EX, EY), exit_cell(EX, EY), Cells);
    .my_name(Me);
    see;
    ?at(Me, RX, RY);
    !sort_by_distance(Cells, RX, RY, Sorted);
    [pos(FX, FY) | _] = Sorted;
    X = FX; Y = FY;
    !clear_nav_state;
    !navigate_adjacent(FX, FY).
