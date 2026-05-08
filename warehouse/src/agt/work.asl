// ═════════════════════════════════════════════════════════════
// WORK.ASL  —  lógica común de trabajo para los robots
//
// Cada robot mantiene creencias locales sobre la topología de
// estanterías y decide por sí mismo a cuál acudir (no depende
// de una asignación explícita del scheduler).
//
// MODELO DE ETIQUETAS:
//   El "tipo" de un paquete es una LISTA Tags que puede contener
//   `urgent`, `fragile`, `standard`. Reglas derivadas:
//     is_urgent_pkg(Tags)  :- .member(urgent, Tags).
//     is_fragile_pkg(Tags) :- .member(fragile, Tags).
//   El grupo de salida lo define la presencia de `urgent`. La etiqueta
//   `fragile` es ortogonal: solo dispara la penalización del 15 % al
//   movimiento (mov.asl, carrying_fragile).
//
// Flujo de un contenedor:
//   1. Scheduler → container_available(CId, W, H, Weight, Tags)
//   2. Robot decide si puede (can_i_manage) y lo encola.
//   3. Al procesarlo, pregunta al scheduler la ubicación y lo recoge.
//   4. Elige LOCALMENTE la estantería compatible (urgent shelves para
//      urgent, regulares para resto) y deposita.
//   5. Al acabar notifica `guardado` al scheduler.
// ═════════════════════════════════════════════════════════════


state(idle).
container_queue([]).

// ─────────────────────────────────────────────────────────────
//  TRAZA DE ESTADOS → SUPERVISOR
//  Cualquier transición state(X) (vía +state, -+state) dispara este
//  plan, que reporta el nuevo estado al supervisor para que lo
//  añada a la traza histórica del robot. La creencia inicial
//  state(idle) NO dispara evento; la traza arranca con la primera
//  transición real (típicamente busy al recibir el primer paquete).
// ─────────────────────────────────────────────────────────────
+state(NewState) <-
    .send(supervisor, tell, robot_status(NewState)).

// ─────────────────────────────────────────────────────────────
//  REGLAS PARA TAGS
// ─────────────────────────────────────────────────────────────
is_urgent_pkg(Tags)  :- .member(urgent,  Tags).
is_fragile_pkg(Tags) :- .member(fragile, Tags).

// ─────────────────────────────────────────────────────────────
//  CARGA FRÁGIL → penalización del 15% al paso
//  carrying_fragile/0 marca que llevamos un paquete con la etiqueta
//  `fragile` (puede ser fragile puro o urgent+fragile combo); mov.asl
//  lo consulta en try_move para multiplicar timePerMove por 1.15.
// ─────────────────────────────────────────────────────────────
+!mark_fragile_if(Tags) : is_fragile_pkg(Tags) <- +carrying_fragile.
+!mark_fragile_if(_).

+!unmark_fragile : carrying_fragile <- -carrying_fragile.
+!unmark_fragile.

// ─────────────────────────────────────────────────────────────
//  CREENCIAS LOCALES: TOPOLOGÍA DE ESTANTERÍAS
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

// Clasificación de las shelves:
urgent_shelf(shelf_1).  urgent_shelf(shelf_5).  urgent_shelf(shelf_8).
regular_shelf(shelf_2). regular_shelf(shelf_3). regular_shelf(shelf_4).
regular_shelf(shelf_6). regular_shelf(shelf_7). regular_shelf(shelf_9).

// Regla de aceptación basada en tags:
//   - Tags con `urgent` → urgent shelves (puro o combo urgent+fragile).
//   - Tags sin `urgent` → regular shelves (standard puro o fragile puro).
accepts(Tags, S) :- .member(urgent, Tags) & urgent_shelf(S).
accepts(Tags, S) :- not .member(urgent, Tags) & regular_shelf(S).

// Celdas libres de la zona de salida.
exit_cell(0,0). exit_cell(0,1). exit_cell(1,0). exit_cell(1,1).
exit_cell(2,0). exit_cell(2,1).

// ─────────────────────────────────────────────────────────────
//  ESTADO COMPARTIDO DE ESTANTERÍAS (peer-to-peer)
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
//  REGLA: el ROBOT MÁS RÁPIDO QUE PUEDE se queda con el paquete.
// ─────────────────────────────────────────────────────────────
+container_available(CId, W, H, Weight, Tags) :
        can_i_manage(W, H, Weight) &
        not faster_capable(W, H, Weight) &
        not is_router_robot <-
    !enqueue(CId, W, H, Weight, Tags);
    .abolish(container_available(CId, _, _, _, _)).

+container_available(CId, W, H, Weight, Tags) : not is_router_robot <-
    .abolish(container_available(CId, _, _, _, _)).

// ─────────────────────────────────────────────────────────────
//  COLA DE CONTENEDORES
//  Si Tags contiene `urgent` se mete al PRINCIPIO de la cola
//  (prioridad de atención), incluido el combo urgent+fragile.
// ─────────────────────────────────────────────────────────────
+!enqueue(CId, W, H, Weight, Tags) :
        is_urgent_pkg(Tags) & container_queue(Q) <-
    -container_queue(_);
    +container_queue([pkg(CId, Weight, W, H, Tags) | Q]);
    .print("Encolado urgente: ", CId, " (tags=", Tags, ")");
    !check_idle.

+!enqueue(CId, W, H, Weight, Tags) : container_queue(Q) <-
    .concat(Q, [pkg(CId, Weight, W, H, Tags)], NewQ);
    -container_queue(_);
    +container_queue(NewQ);
    .print("Encolado: ", CId, " (tags=", Tags, ")");
    !check_idle.

// Si estoy en plena salida, encolo pero no avanzo cola.
+!check_idle : exit_in_progress(_) <- true.
+!check_idle : state(idle) <- !process_next.
+!check_idle : state(going_idle) <-
    .drop_intention(go_idle);
    -+state(idle);
    !process_next.
+!check_idle <- true.

// ─────────────────────────────────────────────────────────────
//  PROCESAR COLA
// ─────────────────────────────────────────────────────────────
+!process_next : exit_in_progress(_) <- true.

+!process_next :
    state(idle) &
    exit_item(_, _, _, _, _, _) <-
    !try_exit_or_fallback.

+!process_next : container_queue([]) <- !go_idle.

+!process_next :
    container_queue([pkg(CId, Weight, W, H, Tags) | Rest]) &
    state(idle) <-
    -+container_queue(Rest);
    -state(idle);
    +state(busy);
    !handle_container(CId, Weight, W, H, Tags).

// ─────────────────────────────────────────────────────────────
//  GESTIÓN DE UN CONTENEDOR
// ─────────────────────────────────────────────────────────────
+!handle_container(CId, Weight, W, H, Tags) <-
    !query_location(CId, CX, CY);
    if (CX == none) {
        .print("Sin ubicación para ", CId, ", descarto tarea");
        -+state(idle);
        !process_next
    } else {
        V = W * H;
        !choose_shelf_local(CId, Tags, Weight, V, Chosen);
        if (Chosen == none) {
            .print("Sin shelf con hueco (incluyendo reservas) para ", CId, " (tags=", Tags, ") — unstorable");
            .send(scheduler, tell, unstorable(CId, Tags));
            -+state(idle);
            !process_next
        } else {
            !reserve_shelf(CId, Chosen, Weight, V);
            !goto_pos(CId, CX, CY);
            pickup(CId);
            !mark_fragile_if(Tags);
            !navigate_to_shelf(Chosen);
            !try_drop(CId, Weight, W, H, Tags, Chosen)
        }
    }.

// ─────────────────────────────────────────────────────────────
//  SELECCIÓN LOCAL DE ESTANTERÍA
//
//  Tags con urgent → urgent shelves ordenadas por distancia Manhattan.
//  Tags sin urgent → robot_shelf_priority del robot, filtrada por
//                    regular_shelf y la blacklist local.
// ─────────────────────────────────────────────────────────────
+!choose_shelf_local(_, Tags, Weight, V, Shelf) : is_urgent_pkg(Tags) <-
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

+!choose_shelf_local(_, Tags, Weight, V, Shelf) :
        not is_urgent_pkg(Tags) & robot_shelf_priority(Prio) <-
    !filter_regular_not_blacklisted(Prio, Filtered);
    !first_fitting(Filtered, Weight, V, Shelf).

// Catch-all: si por alguna razón no aplica → unstorable.
+!choose_shelf_local(CId, Tags, _, _, none) <-
    .print("AVISO: choose_shelf_local sin plan aplicable para ", CId, "/", Tags).

// Lectura segura de la posición.
+!robot_position(X, Y) : .my_name(Me) & at(Me, X, Y).
+!robot_position(X, Y) : idlezone(X, Y) <-
    .print("AVISO: at/3 no disponible — uso idlezone(", X, ",", Y, ") como referencia").

+!filter_regular_not_blacklisted([], []).
+!filter_regular_not_blacklisted([S | T], [S | Rest]) :
        regular_shelf(S) & not shelf_blacklist(S) <-
    !filter_regular_not_blacklisted(T, Rest).
+!filter_regular_not_blacklisted([_ | T], Rest) <-
    !filter_regular_not_blacklisted(T, Rest).

+!first_fitting([], _, _, none).

+!first_fitting([S | Rest], W, V, Chosen) <-
    !shelf_fits(S, W, V, Fits);
    !first_fitting_pick(Fits, S, Rest, W, V, Chosen).

+!first_fitting_pick(true, S, _, _, _, S).
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
    +pending_drop(CId, Shelf, W, V);
    .print("Reservo ", Shelf, " para ", CId, " (w=", W, ", v=", V, ")");
    !peer_broadcast(shelf_reserve(CId, Shelf, W, V)).

+!release_shelf(CId, Shelf, W, V) <-
    .my_name(Me);
    -shelf_reservation(Shelf, Me, W, V, CId);
    -pending_drop(CId, Shelf, W, V);
    .print("Libero reserva ", Shelf, " de ", CId);
    !peer_broadcast(shelf_release(CId, Shelf, W, V)).

@local_commit[atomic]
+!commit_shelf(CId, Shelf, W, V) <-
    .my_name(Me);
    -shelf_reservation(Shelf, Me, W, V, CId);
    -pending_drop(CId, Shelf, W, V);
    !update_usage_local(Shelf, W, V);
    !peer_broadcast(shelf_commit(CId, Shelf, W, V)).

@local_retrieved[atomic]
+!retrieved_shelf(CId, Shelf, W, V) <-
    !update_usage_local(Shelf, -W, -V);
    !peer_broadcast(shelf_retrieved(CId, Shelf, W, V)).

+!update_usage_local(Shelf, DW, DV) :
        shelf_usage_local(Shelf, UW, UV) <-
    NewWraw = UW + DW;
    NewVraw = UV + DV;
    if (NewWraw < 0) { NewW = 0 } else { NewW = NewWraw };
    if (NewVraw < 0) { NewV = 0 } else { NewV = NewVraw };
    .abolish(shelf_usage_local(Shelf, _, _));
    +shelf_usage_local(Shelf, NewW, NewV).

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

@peer_snapshot[atomic]
+shelf_usage_snapshot(L)[source(supervisor)] <-
    !apply_usage_snapshot(L);
    -shelf_usage_snapshot(L)[source(supervisor)].

+!apply_usage_snapshot([]).
+!apply_usage_snapshot([usage(S, W, V) | Rest]) <-
    .abolish(shelf_usage_local(S, _, _));
    +shelf_usage_local(S, W, V);
    !apply_usage_snapshot(Rest).

// ─────────────────────────────────────────────────────────────
//  CONSULTA DE UBICACIÓN AL SCHEDULER
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
// ─────────────────────────────────────────────────────────────
+!try_drop(CId, Weight, W, H, Tags, Shelf) <-
    drop_at(Shelf);
    !unmark_fragile;
    .print("Depositado ", CId, " en ", Shelf);
    !finish_task(CId, Shelf).

-!try_drop(CId, Weight, W, H, Tags, Shelf) <-
    .print("Fallo al depositar ", CId, " en ", Shelf, ", libero reserva y pruebo otra...");
    V = W * H;
    !release_shelf(CId, Shelf, Weight, V);
    +shelf_blacklist(Shelf);
    !choose_shelf_local(CId, Tags, Weight, V, Alt);
    if (Alt == none) {
        .wait(2000);
        !choose_shelf_local(CId, Tags, Weight, V, Retry);
        if (Retry == none) {
            .print("Sigo sin alternativa para ", CId, " — caso límite: salida directa + ciclo de salida");
            !force_exit_carried(CId, Tags);
            -+state(idle);
            !process_next
        } else {
            !reserve_shelf(CId, Retry, Weight, V);
            !navigate_to_shelf(Retry);
            !try_drop(CId, Weight, W, H, Tags, Retry)
        }
    } else {
        !reserve_shelf(CId, Alt, Weight, V);
        !navigate_to_shelf(Alt);
        !try_drop(CId, Weight, W, H, Tags, Alt)
    }.

// ─────────────────────────────────────────────────────────────
//  FINALIZAR TAREA
// ─────────────────────────────────────────────────────────────
+!force_exit_carried(CId, Tags) <-
    !release_if_reserved(CId);
    !go_to_exit_cell(EX, EY);
    drop_at_exit(EX, EY);
    log_event(container_delivered, CId);
    .my_name(MeEv); .print("EVENT | agent=", MeEv, " | type=container_delivered | data=", CId);
    !unmark_fragile;
    .send(scheduler, tell, force_exit_cycle(Tags));
    .print("Caso límite: ", CId, " entregado a la salida y ciclo solicitado (tags=", Tags, ").").

+!finish_task(CId, Shelf) :
        .my_name(Me) & shelf_reservation(Shelf, Me, W, V, CId) <-
    !commit_shelf(CId, Shelf, W, V);
    .send(scheduler, tell, guardado(CId, Shelf, W, V));
    +my_stored(CId, Shelf, W, V);
    .abolish(shelf_blacklist(_));
    -+state(idle);
    .print("Completado: ", CId, " → ", Shelf);
    !process_next.

+!finish_task(CId, Shelf) :
        pending_drop(CId, Shelf, W, V) <-
    .print("RECUPERACIÓN: reserva purgada por deadline para ", CId,
           " — recupero W=", W, " V=", V, " de pending_drop");

    !commit_shelf(CId, Shelf, W, V);
    .send(scheduler, tell, guardado(CId, Shelf, W, V));
    +my_stored(CId, Shelf, W, V);
    .abolish(shelf_blacklist(_));
    -+state(idle);
    !process_next.

+!finish_task(CId, Shelf) <-
    .print("AVISO GRAVE: finish_task sin reserva NI pending_drop para ", CId,
           " en ", Shelf, " — paquete potencialmente huérfano");

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
//  CONTENEDOR DESTRUIDO (splash)
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
    .abolish(delegated_stored(CId, _, _, _));
    .abolish(delegating(CId));
    .abolish(pending_drop(CId, _, _, _));
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

+!release_if_reserved(CId) :
        .my_name(Me) & shelf_reservation(Shelf, Me, W, V, CId) <-
    !release_shelf(CId, Shelf, W, V).
+!release_if_reserved(_).

// ═════════════════════════════════════════════════════════════
//  RECUPERACIÓN: paquete en mano + tarea fallida
// ═════════════════════════════════════════════════════════════
+!recover_carrying : picked(CId) <-
    .print("Recuperación: tengo ", CId, " en la mano — lo entrego en la salida");
    !release_if_reserved(CId);
    !clear_nav_state;
    !go_to_exit_cell(EX, EY);
    drop_at_exit(EX, EY);
    log_event(container_delivered, CId);
    .my_name(MeEv); .print("EVENT | agent=", MeEv, " | type=container_delivered | data=", CId);
    !unmark_fragile;
    .print("Recuperación: ", CId, " entregado en la salida").
+!recover_carrying.

-!recover_carrying <-
    .print("AVISO: recuperación de paquete en mano no completó (puede quedar carrying)").

// ═════════════════════════════════════════════════════════════
//  FALLOS DE handle_container — limpieza segura
// ═════════════════════════════════════════════════════════════
-!handle_container(CId, _, _, _, _) <-
    .print("AVISO: handle_container(", CId, ") falló — recupero estado");
    !release_if_reserved(CId);
    !recover_carrying;
    .abolish(shelf_blacklist(_));
    -+state(idle);
    !process_next.

// ═════════════════════════════════════════════════════════════
//  CICLO DE SALIDA POR DEADLINES
// ═════════════════════════════════════════════════════════════

can_i_manage_weight(Weight) :-
    max_weight(MaxW) & Weight <= MaxW.

can_i_exit(CId, at_shelf(_))   :- my_stored(CId, _, _, _).
can_i_exit(CId, at_shelf(_))   :- delegated_stored(CId, _, _, _).
can_i_exit(_,   at_entry(_,_)).

owned_dim(CId, Shelf, W, V) :- my_stored(CId, Shelf, W, V).
owned_dim(CId, Shelf, W, V) :- delegated_stored(CId, Shelf, W, V).

+!consume_owned(CId, Shelf, W, V) : my_stored(CId, Shelf, W, V) <-
    -my_stored(CId, Shelf, W, V).
+!consume_owned(CId, Shelf, W, V) : delegated_stored(CId, Shelf, W, V) <-
    -delegated_stored(CId, Shelf, W, V).
+!consume_owned(CId, _, _, _) <-
    .print("AVISO: consume_owned sin propietario para ", CId).

// ─── Recepción de un exit_item ──────────────────────────────
+exit_item(CId, _, W, _, Tags, Kind)[source(scheduler)] :
        can_i_manage_weight(W) <-
    .print("Recibido exit_item ", CId, " (tags ", Tags, ", ", Kind, ")");
    !check_idle.

+exit_item(_, _, _, _, _, _)[source(scheduler)] <- true.

+exit_taken(CId)[source(scheduler)] <-
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_taken(CId)[source(scheduler)].

// Inicio/fin de deadline.
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
@try_exit_atomic[atomic]
+!try_exit_or_fallback : not exit_in_progress(_) <-
    !pick_best_exit_item(Best);
    if (Best == none) {
        !try_help_then_fallback
    } else {
        Best = ex(CId, Loc, _, _, Tags, _);
        .print("Elijo exit_item ", CId, " (", Loc, "), pido claim");
        +exit_in_progress(CId);
        +pending_claim(CId, Loc, Tags);
        -+state(busy);
        .drop_intention(go_idle);
        .my_name(Me);
        .abolish(claim_result(CId, _));
        .send(scheduler, achieve, claim_exit(CId, Me))
    }.

+!try_exit_or_fallback <- true.

+!fallback_to_normal : container_queue([]) <- !go_idle.
+!fallback_to_normal :
        container_queue([pkg(CId, Weight, W, H, Tags) | Rest]) <-
    -+container_queue(Rest);
    -state(idle);
    +state(busy);
    !handle_container(CId, Weight, W, H, Tags).

// ═════════════════════════════════════════════════════════════
//  PROTOCOLO DE AYUDA EN CICLO DE SALIDA
// ═════════════════════════════════════════════════════════════

+!try_help_then_fallback : active_deadline(_) & not asked_for_help_round <-
    +asked_for_help_round;
    !ask_for_help.

+!try_help_then_fallback <-
    .abolish(asked_for_help_round);
    !fallback_to_normal.

+!ask_for_help : max_weight(MyMaxW) <-
    .my_name(Me);
    .abolish(help_offer(_, _, _, _, _)[source(_)]);
    .print("HELP: pido ayuda (maxW=", MyMaxW, ")");
    !peer_broadcast(help_request(Me, MyMaxW));
    .wait(800);
    .findall(ho(P, CId, S, W, V, T),
             help_offer(CId, S, W, V, T)[source(P)],
             Offers);
    .abolish(help_offer(_, _, _, _, _)[source(_)]);
    !pick_closest_offer(Offers, none, 999999, Best);
    !consume_help_offer(Best).

+!consume_help_offer(none) <-
    -asked_for_help_round;
    .print("HELP: nadie ofrece — paso a entrada");
    !fallback_to_normal.

+!consume_help_offer(ho(P, CId, S, W, V, Tags)) <-
    .my_name(Me);
    .abolish(help_confirm(CId, _, _, _, _)[source(P)]);
    .abolish(help_deny(CId)[source(P)]);
    .print("HELP: acepto oferta de ", P, " — ", CId, " en ", S);
    .send(P, achieve, help_take(Me, CId));
    .wait(1500);
    !finalize_help(P, CId).

+!finalize_help(P, CId) :
        help_confirm(CId, Sh, CW, CV, _)[source(P)] <-
    -help_confirm(CId, Sh, CW, CV, _)[source(P)];
    +delegated_stored(CId, Sh, CW, CV);
    -asked_for_help_round;
    .print("HELP: tomo ", CId, " de ", P, " — re-evalúo exit_items");
    !try_exit_or_fallback.

+!finalize_help(P, CId) <-
    .abolish(help_deny(CId)[source(P)]);
    -asked_for_help_round;
    .print("HELP: ", P, " denegó ", CId, " — fallback");
    !fallback_to_normal.

+!pick_closest_offer([], Cur, _, Cur).
+!pick_closest_offer([ho(P, CId, S, W, V, Tags) | Rest], Cur, MinD, Best) <-
    !robot_position(RX, RY);
    !offer_distance(S, RX, RY, D);
    if (D < MinD) {
        !pick_closest_offer(Rest, ho(P, CId, S, W, V, Tags), D, Best)
    } else {
        !pick_closest_offer(Rest, Cur, MinD, Best)
    }.

+!offer_distance(S, RX, RY, D) : shelf_location(S, SX, SY) <-
    D = math.abs(SX - RX) + math.abs(SY - RY).
+!offer_distance(_, _, _, 999998).

// ─── Lado P: responder ofertas y compromiso ────────────────────
+help_request(Asker, MaxW)[source(Asker)] : not evaluating_help_requests <-
    +evaluating_help_requests;
    .wait(300);
    .findall(req(A, MW), help_request(A, MW)[source(A)], Reqs);
    .abolish(help_request(_, _)[source(_)]);
    !pick_heaviest_servable(Reqs, none, -1, Best);
    -evaluating_help_requests;
    !respond_to_best(Best).

+help_request(_, _)[source(_)] : evaluating_help_requests.

+!pick_heaviest_servable([], Cur, _, Cur).
+!pick_heaviest_servable([req(A, MW) | Rest], Cur, BestMW, Best) <-
    !find_offerable(MW, Offer);
    if (Offer \== none & MW > BestMW) {
        !pick_heaviest_servable(Rest, sel(A, Offer), MW, Best)
    } else {
        !pick_heaviest_servable(Rest, Cur, BestMW, Best)
    }.

+!respond_to_best(none).
+!respond_to_best(sel(Asker, of(CId, Shelf, W, V, Tags))) <-
    .send(Asker, tell, help_offer(CId, Shelf, W, V, Tags));
    .print("HELP: ofrezco ", CId, " (", Shelf, ") a ", Asker, " — solicitante más pesado servible").

+!find_offerable(MaxW, Offer) <-
    .findall(of(CId, Shelf, W, V, Tags),
             (my_stored(CId, Shelf, W, V) &
              exit_item(CId, at_shelf(Shelf), W, V, Tags, _) &
              W <= MaxW &
              not delegating(CId)),
             L);
    !first_or_none(L, Offer).

+!first_or_none([], none).
+!first_or_none([H | _], H).

+!help_take(Asker, CId)[source(Asker)] :
        my_stored(CId, Shelf, W, V) & not delegating(CId) <-
    +delegating(CId);
    -my_stored(CId, Shelf, W, V);
    ?exit_item(CId, _, _, _, Tags, _);
    .send(Asker, tell, help_confirm(CId, Shelf, W, V, Tags));
    -delegating(CId);
    .print("HELP: cedido ", CId, " a ", Asker, " — borrado de mi my_stored").

+!help_take(Asker, CId)[source(Asker)] <-
    .send(Asker, tell, help_deny(CId));
    .print("HELP: deniego ", CId, " a ", Asker, " (ya no es mío)").

// Defensa en profundidad: SÓLO consideramos exit_items cuyo Kind coincide
// con un active_deadline(Kind) vigente.
+!pick_best_exit_item(Best) <-
    .my_name(Me);
    see;
    !robot_position(RX, RY);
    .findall(ex(CId, Loc, W, V, Tags, Kind),
             (active_deadline(Kind) &
              exit_item(CId, Loc, W, V, Tags, Kind) &
              can_i_manage_weight(W) &
              can_i_exit(CId, Loc)),
             Cands);
    !pick_closest_exit(Cands, RX, RY, none, 999999, Best).

+!pick_closest_exit([], _, _, Best, _, Best).
+!pick_closest_exit([ex(CId, Loc, W, V, Tags, Kind) | Rest], RX, RY, Cur, MinD, Best) <-
    !dist_to_loc(Loc, RX, RY, D);
    if (D < MinD) {
        !pick_closest_exit(Rest, RX, RY, ex(CId, Loc, W, V, Tags, Kind), D, Best)
    } else {
        !pick_closest_exit(Rest, RX, RY, Cur, MinD, Best)
    }.

+!dist_to_loc(at_shelf(S), RX, RY, D) :
        shelf_location(S, SX, SY) <-
    D = math.abs(SX - RX) + math.abs(SY - RY).
+!dist_to_loc(at_entry(X, Y), RX, RY, D) <-
    D = math.abs(X - RX) + math.abs(Y - RY).

// ─── Respuesta del claim (event-driven, no .wait) ───────────
+claim_result(CId, granted)[source(scheduler)] :
        pending_claim(CId, Loc, Tags) <-
    -claim_result(CId, granted)[source(scheduler)];
    -pending_claim(CId, Loc, Tags);
    !execute_exit(CId, Loc, Tags).

+claim_result(CId, denied)[source(scheduler)] :
        pending_claim(CId, _, _) <-
    .print("Claim denegado para ", CId, " — libero y reintento");
    -claim_result(CId, denied)[source(scheduler)];
    .abolish(pending_claim(CId, _, _));
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

+claim_result(_, _)[source(scheduler)] <-
    .abolish(claim_result(_, _)[source(scheduler)]).

// ─────────────────────────────────────────────────────────────
//  EXIT CON GUARDAS DE DEADLINE
// ─────────────────────────────────────────────────────────────
+!execute_exit(CId, at_shelf(Shelf), Tags) <-
    .print("Exit de ", CId, " desde shelf ", Shelf);
    !navigate_to_shelf(Shelf);
    if (not active_deadline(_)) {
        .print("Deadline cerrado antes de retrieve de ", CId, " — abandono exit");
        !abort_exit_cleanup(CId)
    } else {
        retrieve(CId);
        !mark_fragile_if(Tags);
        ?owned_dim(CId, Shelf, W, V);
        !consume_owned(CId, Shelf, W, V);
        !retrieved_shelf(CId, Shelf, W, V);
        +carrying_exit(CId, Tags, Shelf, W, V);
        !go_to_exit_cell(EX, EY);
        if (not active_deadline(_)) {
            .print("Deadline cerrado durante traslado a salida con ", CId, " — re-almaceno");
            !reshelf_carried(CId, Tags, Shelf, W, V)
        } else {
            drop_at_exit(EX, EY);
            log_event(container_delivered, CId);
            .my_name(MeEv); .print("EVENT | agent=", MeEv, " | type=container_delivered | data=", CId);
            !unmark_fragile;
            .abolish(carrying_exit(CId, _, _, _, _));
            .send(scheduler, tell, exit_done(CId, Tags));
            .abolish(exit_item(CId, _, _, _, _, _));
            -exit_in_progress(_);
            -+state(idle);
            .print("Exit completo: ", CId);
            !process_next
        }
    }.

+!execute_exit(CId, at_entry(X, Y), Tags) <-
    .print("Exit directo de ", CId, " desde entrada (", X, ",", Y, ")");
    !goto_pos(CId, X, Y);
    if (not active_deadline(_)) {
        .print("Deadline cerrado antes de pickup de ", CId, " — abandono exit");
        !abort_exit_cleanup(CId)
    } else {
        pickup(CId);
        !mark_fragile_if(Tags);
        !get_exit_dim(CId, EW, EV);
        +carrying_exit(CId, Tags, none, EW, EV);
        !go_to_exit_cell(EX, EY);
        if (not active_deadline(_)) {
            .print("Deadline cerrado durante traslado a salida con ", CId, " — re-almaceno");
            !reshelf_carried(CId, Tags, none, EW, EV)
        } else {
            drop_at_exit(EX, EY);
            log_event(container_delivered, CId);
            .my_name(MeEv); .print("EVENT | agent=", MeEv, " | type=container_delivered | data=", CId);
            !unmark_fragile;
            .abolish(carrying_exit(CId, _, _, _, _));
            .send(scheduler, tell, exit_done(CId, Tags));
            .abolish(exit_item(CId, _, _, _, _, _));
            -exit_in_progress(_);
            -+state(idle);
            .print("Exit directo completo: ", CId);
            !process_next
        }
    }.

-!execute_exit(CId, _, Tags) <-
    .print("Fallo el exit de ", CId, " — recupero estado");
    !recover_carrying;
    .abolish(carrying_exit(CId, _, _, _, _));
    .send(scheduler, tell, exit_done(CId, Tags));
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

+!abort_exit_cleanup(CId) <-
    .abolish(pending_claim(CId, _, _));
    .abolish(exit_item(CId, _, _, _, _, _));
    .abolish(carrying_exit(CId, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

// ─────────────────────────────────────────────────────────────
//  RE-ALMACENAMIENTO TRAS FIN DE DEADLINE
// ─────────────────────────────────────────────────────────────
+!reshelf_carried(CId, Tags, _, W, V) <-
    !choose_shelf_local(CId, Tags, W, V, Chosen);
    !reshelf_carried_dispatch(CId, Tags, W, V, Chosen).

+!reshelf_carried_dispatch(CId, Tags, _, _, none) <-
    .print("AVISO: sin shelf libre para re-almacenar ", CId, " — caso límite: salida directa + ciclo");
    !force_exit_carried(CId, Tags);
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
    !unmark_fragile;
    .print("Re-almacenado ", CId, " en ", Shelf, " (deadline expiró durante salida)");
    !commit_shelf(CId, Shelf, W, V);
    .send(scheduler, tell, guardado(CId, Shelf, W, V));
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
    ?carrying_exit(CId, Tags, OrigShelf, _, _);
    !reshelf_carried(CId, Tags, OrigShelf, W, V).

+!get_exit_dim(CId, W, V) : exit_item(CId, _, EW, EV, _, _) <-
    W = EW; V = EV.
+!get_exit_dim(_, 0, 0).

+!go_to_exit_cell(X, Y) <-
    .findall(pos(EX, EY), exit_cell(EX, EY), Cells);
    !navigate_to_any(Cells);
    .my_name(Me);
    see;
    ?at(Me, RX, RY);
    X = RX; Y = RY.
