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
// ─────────────────────────────────────────────────────────────
+!handle_container(CId, Weight, W, H, Type) <-
    !query_location(CId, CX, CY);
    if (CX == none) {
        .print("Sin ubicación para ", CId, ", descarto tarea");
        -+state(idle);
        !process_next
    } else {
        // ── 1) PEDIR SUGERENCIA AL SCHEDULER ANTES DE RECOGER ─────────
        //    Si el scheduler dice que no hay shelf disponible, marcamos
        //    el paquete como unstorable y NO lo recogemos.
        !ask_shelf_suggestion(CId, Type, Suggested);
        if (Suggested == none) {
            .print("Scheduler dice sin shelf para ", CId, " (tipo ", Type, "). No lo recojo.");
            .my_name(Me);
            .send(scheduler, tell, unstorable(CId, Type));
            -+state(idle);
            !process_next
        } else {
            +suggested_shelf(CId, Suggested);
            !goto_pos(CId, CX, CY);
            pickup(CId);
            !pick_shelf(CId, Weight, W, H, Type, TargetShelf);
            if (TargetShelf == none) {
                .print("Sin estantería disponible para ", CId, " tras pickup, reintento en 2s...");
                .wait(2000);
                !handle_container(CId, Weight, W, H, Type)
            } else {
                !navigate_to_shelf(TargetShelf);
                !try_drop(CId, Weight, W, H, Type, TargetShelf);
                !finish_task(CId, TargetShelf)
            }
        }
    }.

// Pregunta bloqueante al scheduler: ¿qué shelf usar para este CId?
// Espera SIEMPRE hasta obtener respuesta — nunca marca unstorable por timeout.
// Si hay timeout, reenvía la petición y sigue esperando.
+!ask_shelf_suggestion(CId, Type, Shelf) <-
    .my_name(Me);
    see;
    ?at(Me, RX, RY);
    .abolish(shelf_suggestion(CId, _));
    .send(scheduler, achieve, suggest_shelf(CId, Type, RX, RY, Me));
    !wait_shelf_response(CId, Type, Shelf).

+!wait_shelf_response(CId, _, Shelf) : shelf_suggestion(CId, S) <-
    Shelf = S;
    .abolish(shelf_suggestion(CId, _)).

+!wait_shelf_response(CId, Type, Shelf) <-
    .wait({+shelf_suggestion(CId, _)}, 15000, _);
    if (shelf_suggestion(CId, S)) {
        Shelf = S;
        .abolish(shelf_suggestion(CId, _))
    } else {
        .print("Timeout esperando shelf_suggestion de ", CId, ", reenvío petición...");
        .my_name(Me);
        see;
        ?at(Me, RX, RY);
        .send(scheduler, achieve, suggest_shelf(CId, Type, RX, RY, Me));
        !wait_shelf_response(CId, Type, Shelf)
    }.

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
        .print("Confirmación ", CId, " falló — continúo con última posición")
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
//  SELECCIÓN LOCAL DE ESTANTERÍA
//  Cada robot elige por distancia entre las que aceptan el tipo
//  y que no están en su lista negra. Si drop_at falla, el shelf
//  se añade a shelf_blacklist/1 y se reintenta con el siguiente.
// ─────────────────────────────────────────────────────────────
// 1º intento: usar la sugerencia que nos dio el scheduler (si sigue viva).
+!pick_shelf(CId, _, _, _, _, Shelf) :
        suggested_shelf(CId, S) & not shelf_blacklist(S) <-
    Shelf = S;
    -suggested_shelf(CId, S).

// Fallback (drop anterior falló, o sugerencia ya blacklisted): la más cercana
// entre las que aceptan el tipo y no están en la blacklist local.
+!pick_shelf(_, _, _, _, Type, Shelf) <-
    .my_name(Me);
    see;
    ?at(Me, RX, RY);
    .findall(S, (accepts(Type, S) & not shelf_blacklist(S)), Cands);
    !sort_shelves_by_distance(Cands, RX, RY, Sorted);
    if (Sorted == []) {
        Shelf = none
    } else {
        [Shelf | _] = Sorted
    }.

+!sort_shelves_by_distance([], _, _, []).
+!sort_shelves_by_distance(L, RX, RY, [Best | Rest]) <-
    !closest_shelf(L, RX, RY, 999999, none, Best);
    .delete(Best, L, Without);
    !sort_shelves_by_distance(Without, RX, RY, Rest).

+!closest_shelf([], _, _, _, B, B).
+!closest_shelf([S | T], RX, RY, MinD, Cur, Best) :
        shelf_location(S, SX, SY) <-
    D = math.abs(SX - RX) + math.abs(SY - RY);
    if (D < MinD) {
        !closest_shelf(T, RX, RY, D, S, Best)
    } else {
        !closest_shelf(T, RX, RY, MinD, Cur, Best)
    }.
+!closest_shelf([_ | T], RX, RY, MinD, Cur, Best) <-
    !closest_shelf(T, RX, RY, MinD, Cur, Best).

// ─────────────────────────────────────────────────────────────
//  DEPOSITAR
// ─────────────────────────────────────────────────────────────
+!try_drop(CId, Weight, W, H, Type, Shelf) <-
    drop_at(Shelf);
    .print("Depositado ", CId, " en ", Shelf).

-!try_drop(CId, Weight, W, H, Type, Shelf) <-
    .print("Fallo al depositar ", CId, " en ", Shelf, ", la descarto y pruebo otra...");
    +shelf_blacklist(Shelf);
    !pick_shelf(CId, Weight, W, H, Type, AltShelf);
    if (AltShelf == none) {
        .print("Sin alternativa para ", CId, ", reintento en 2s...");
        .wait(2000);
        !pick_shelf(CId, Weight, W, H, Type, Retry);
        if (Retry == none) {
            .print("Sigo sin alternativa para ", CId, " — abandono");
            -+state(idle);
            !process_next
        } else {
            !navigate_to_shelf(Retry);
            !try_drop(CId, Weight, W, H, Type, Retry)
        }
    } else {
        !navigate_to_shelf(AltShelf);
        !try_drop(CId, Weight, W, H, Type, AltShelf)
    }.

// ─────────────────────────────────────────────────────────────
//  FINALIZAR TAREA → notificar al scheduler vía guardado
// ─────────────────────────────────────────────────────────────
+!finish_task(CId, Shelf) <-
    task_complete(CId, Shelf);
    .send(scheduler, tell, guardado(CId, Shelf));
    // Memoria local de ownership: "este CId lo guardé yo". Se usa durante
    // los deadlines para que sólo su dueño intente sacarlo del almacén.
    +my_stored(CId);
    // Depositado OK → limpiamos blacklists que hubiéramos marcado por fallos
    // puntuales; así el próximo drop vuelve a considerar todas las shelves.
    .abolish(shelf_blacklist(_));
    .abolish(suggested_shelf(CId, _));
    -+state(idle);
    .print("Completado: ", CId, " → ", Shelf);
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
//   · los paquetes que él mismo guardó (at_shelf + my_stored)
//   · los unstorable que quedaron en la entrada (at_entry, sin dueño)
// Así el scheduler no tiene que asignar nadie: cada robot filtra solo.
can_i_exit(CId, at_shelf(_))   :- my_stored(CId).
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

// Inicio/fin de deadline: sólo informativo + intento de despertar
+active_deadline(Kind)[source(scheduler)] <-
    .print("Robot: deadline activo ", Kind);
    !check_idle.

-active_deadline(Kind)[source(scheduler)] <-
    .print("Robot: deadline ", Kind, " cerrado").

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

+!pick_best_exit_item(Best) <-
    .my_name(Me);
    see;
    ?at(Me, RX, RY);
    .findall(ex(CId, Loc, W, V, Type, Kind),
             (exit_item(CId, Loc, W, V, Type, Kind) &
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

+!execute_exit(CId, at_shelf(Shelf), Type) <-
    .print("Exit de ", CId, " desde shelf ", Shelf);
    !navigate_to_shelf(Shelf);
    retrieve(CId);
    !go_to_exit_cell(EX, EY);
    drop_at_exit(EX, EY);
    // Ya lo saqué: libero mi ownership local.
    -my_stored(CId);
    .send(scheduler, tell, exit_done(CId, Type));
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    .print("Exit completo: ", CId);
    !process_next.

+!execute_exit(CId, at_entry(X, Y), Type) <-
    .print("Exit directo de ", CId, " desde entrada (", X, ",", Y, ")");
    !goto_pos(CId, X, Y);
    pickup(CId);
    !go_to_exit_cell(EX, EY);
    drop_at_exit(EX, EY);
    .send(scheduler, tell, exit_done(CId, Type));
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    .print("Exit directo completo: ", CId);
    !process_next.

-!execute_exit(CId, _, Type) <-
    .print("Fallo el exit de ", CId);
    .send(scheduler, tell, exit_done(CId, Type));
    .abolish(exit_item(CId, _, _, _, _, _));
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

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
