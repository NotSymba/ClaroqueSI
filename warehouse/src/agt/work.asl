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
// Ciclo de salida (exit_order):
//   El scheduler pide desalojar un paquete concreto de una shelf
//   al saturarse el tipo. El robot que pueda cargarlo lo retrieve
//   y lo deposita en una celda libre de la zona de salida.
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
// al terminar exit (ver do_exit / do_exit_direct).
+!check_idle : exit_in_progress(_) <- true.
+!check_idle : state(idle) <- !process_next.
+!check_idle : state(going_idle) <-
    .drop_intention(go_idle);
    -+state(idle);
    !process_next.
+!check_idle <- true.

// ─────────────────────────────────────────────────────────────
//  PROCESAR COLA
//  Prioridad: exit_order pendiente > exit_direct_order pendiente >
//             cola normal > ir a idle.
// ─────────────────────────────────────────────────────────────
+!process_next : exit_in_progress(_) <- true.

+!process_next :
    state(idle) &
    exit_order(CId, Shelf, Weight, V, Type)[source(scheduler)] &
    can_i_manage_weight(Weight) <-
    -exit_order(CId, Shelf, Weight, V, Type)[source(scheduler)];
    +exit_in_progress(CId);
    -+state(busy);
    .print("Retomo exit_order pendiente ", CId);
    !do_exit(CId, Shelf).

+!process_next :
    state(idle) &
    exit_direct_order(CId, Weight, V, Type)[source(scheduler)] &
    can_i_manage_weight(Weight) <-
    -exit_direct_order(CId, Weight, V, Type)[source(scheduler)];
    +exit_in_progress(CId);
    -+state(busy);
    .print("Retomo exit_direct_order pendiente ", CId);
    !do_exit_direct(CId).

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
+!ask_shelf_suggestion(CId, Type, Shelf) <-
    .my_name(Me);
    see;
    ?at(Me, RX, RY);
    .abolish(shelf_suggestion(CId, _));
    .send(scheduler, achieve, suggest_shelf(CId, Type, RX, RY, Me));
    .wait({+shelf_suggestion(CId, _)}, 3000, _);
    if (shelf_suggestion(CId, S)) {
        Shelf = S;
        .abolish(shelf_suggestion(CId, _));
    } else {
        .print("Timeout esperando shelf_suggestion de ", CId);
        Shelf = none
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
//  CICLO DE SALIDA (exit_order del scheduler)
//  El scheduler envía exit_order(CId, Shelf, Weight, V, Type) a
//  varios robots; el primero que pueda cargarlo y esté libre lo
//  ejecuta. Los demás lo descartan.
// ═════════════════════════════════════════════════════════════
+exit_order(CId, Shelf, Weight, V, Type)[source(scheduler)] :
        can_i_manage_weight(Weight) & not exit_in_progress(_) &
        (state(idle) | state(going_idle)) <-
    +exit_in_progress(CId);
    .drop_intention(go_idle);
    -+state(busy);
    .print("Acepto exit_order para ", CId, " desde ", Shelf);
    !do_exit(CId, Shelf);
    -exit_order(CId, Shelf, Weight, V, Type)[source(scheduler)].

// Puedo cargarlo pero estoy ocupado → dejo el belief como "pendiente".
// process_next lo recogerá como prioritario cuando vuelva a idle.
+exit_order(CId, _, Weight, _, _)[source(scheduler)] :
        can_i_manage_weight(Weight) <-
    .print("exit_order ", CId, " pendiente (robot ocupado)").

// No puedo con el peso → aviso al scheduler para que retire.
+exit_order(CId, Shelf, Weight, V, Type)[source(scheduler)] <-
    .print("No puedo con exit_order ", CId, " (peso=", Weight, ")");
    -exit_order(CId, Shelf, Weight, V, Type)[source(scheduler)];
    .send(scheduler, tell, exit_reject(CId, Shelf, Weight, V, Type)).

// Regla auxiliar: ¿puedo cargar este peso? (las dimensiones del paquete
// almacenado son desconocidas aquí, confiamos en el scheduler y en que
// el entorno rechazará si hay error).
can_i_manage_weight(Weight) :-
    max_weight(MaxW) & Weight <= MaxW.

+!do_exit(CId, Shelf) <-
    !navigate_to_shelf(Shelf);
    retrieve(CId);
    !go_to_exit_cell(ExitX, ExitY);
    drop_at_exit(ExitX, ExitY);
    .print("Exit completo para ", CId);
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

-!do_exit(CId, _) <-
    .print("Fallo el exit de ", CId);
    -exit_in_progress(_);
    -+state(idle);
    !process_next.

// ─────────────────────────────────────────────────────────────
//  SALIDA DIRECTA (paquetes unstorable que están en zona de entrada)
//  El scheduler los manda al exit sin pasar por shelf. El robot los
//  recoge de la zona de entrada igual que un pickup normal y los
//  deposita en una celda de salida libre.
// ─────────────────────────────────────────────────────────────
+exit_direct_order(CId, Weight, V, Type)[source(scheduler)] :
        can_i_manage_weight(Weight) & not exit_in_progress(_) &
        (state(idle) | state(going_idle)) <-
    +exit_in_progress(CId);
    .drop_intention(go_idle);
    -+state(busy);
    .print("Acepto exit_direct_order de ", CId, " (tipo ", Type, ")");
    !do_exit_direct(CId);
    -exit_direct_order(CId, Weight, V, Type)[source(scheduler)].

// Ocupado → queda pendiente
+exit_direct_order(CId, Weight, _, _)[source(scheduler)] :
        can_i_manage_weight(Weight) <-
    .print("exit_direct_order ", CId, " pendiente (robot ocupado)").

+exit_direct_order(CId, Weight, V, Type)[source(scheduler)] <-
    .print("No puedo con exit_direct_order ", CId, " (peso=", Weight, ")");
    -exit_direct_order(CId, Weight, V, Type)[source(scheduler)];
    .send(scheduler, tell, exit_reject(CId, none, Weight, V, Type)).

+!do_exit_direct(CId) <-
    !query_location(CId, CX, CY);
    if (CX == none) {
        .print("exit_direct: sin ubicación para ", CId);
        -exit_in_progress(_);
        -+state(idle);
        !process_next
    } else {
        !goto_pos(CId, CX, CY);
        pickup(CId);
        !go_to_exit_cell(EX, EY);
        drop_at_exit(EX, EY);
        .print("exit_direct completado para ", CId);
        -exit_in_progress(_);
        -+state(idle);
        !process_next
    }.

-!do_exit_direct(CId) <-
    .print("Fallo el exit_direct de ", CId);
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
