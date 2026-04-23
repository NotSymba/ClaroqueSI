/*******************************************************************************
 * SCHEDULER - Agente planificador
 *
 * Responsabilidades:
 *   1. Garantizar accesibilidad de los paquetes en la zona de entrada /
 *      clasificación (reubica si algún paquete queda atrapado).
 *   2. Punto central de información: responde a consultas de los robots sobre
 *      la ubicación de los contenedores. NO asigna robots ni estanterías.
 *   3. Recibe el aviso del supervisor cuando no queda espacio para un tipo
 *      concreto (no_space(Type)):
 *         - bloquea la aceptación de nuevos contenedores de ese tipo
 *         - lanza un ciclo de salida: pide a un robot que saque un paquete
 *           almacenado de ese tipo y lo deposite en la zona de salida
 *   4. Cuando el supervisor avisa que el tipo vuelve a tener espacio
 *      (space_available(Type)), desbloquea y vuelca la cola de contenedores
 *      pendientes a los robots.
 *
 * Lo que el scheduler NO hace:
 *   - No elige qué estantería usa cada robot (cada robot decide localmente)
 *   - No asigna contenedores a robots concretos (los anuncia a todos y cada
 *     robot decide si le corresponde por capacidad)
 ******************************************************************************/

/* ============================================================================
 * TOPOLOGÍA DE ZONAS (coincide con WarehouseModel.initializeGrid)
 *   Zona de salida:        x in [0..2], y in [0..1]
 *   Zona de clasificación: x in [3..4], y in [0..1]
 *   Zona de entrada:       x in [5..7], y in [0..1]
 *   Celdas EMPTY alcanzables desde zona:
 *     (x, 2) para x in [3..7]
 *     (8, 0), (8, 1)
 * ============================================================================ */

zone_cell(3,0). zone_cell(3,1). zone_cell(4,0). zone_cell(4,1).
zone_cell(5,0). zone_cell(5,1). zone_cell(6,0). zone_cell(6,1).
zone_cell(7,0). zone_cell(7,1).

classification_cell(3,0). classification_cell(3,1).
classification_cell(4,0). classification_cell(4,1).

empty_exit(3,2). empty_exit(4,2). empty_exit(5,2). empty_exit(6,2). empty_exit(7,2).
empty_exit(8,0). empty_exit(8,1).

/* Celdas de la zona de SALIDA (para el ciclo de salida). Se elige una libre
 * al depositar. */
exit_cell(0,0). exit_cell(0,1). exit_cell(1,0). exit_cell(1,1).
exit_cell(2,0). exit_cell(2,1).

/* ----------------------------------------------------------------------------
 *  ESTANTERÍAS: ubicación, tipos admitidos y listas de prioridad por robot.
 *    light  : [2,3,4,6,7,9]
 *    medium : [6,7,2,3,4,9]
 *    heavy* : [9,6,7,2,3,4]
 *  Urgentes (shelves 1,5,8): se sugiere siempre la más cercana al robot.
 *  La ocupación real la gestiona el SUPERVISOR — el scheduler sólo construye
 *  la lista ordenada y delega en él la elección final (ver suggest_shelf).
 * -------------------------------------------------------------------------- */
shelf_location(shelf_1, 10,  2). shelf_location(shelf_2, 12,  2).
shelf_location(shelf_3, 14,  2). shelf_location(shelf_4, 16,  2).
shelf_location(shelf_5, 10,  6). shelf_location(shelf_6, 13,  6).
shelf_location(shelf_7, 16,  6).
shelf_location(shelf_8, 10, 10). shelf_location(shelf_9, 14, 10).

shelf_accepts(urgent,   shelf_1).
shelf_accepts(urgent,   shelf_5).
shelf_accepts(urgent,   shelf_8).
shelf_accepts(standard, shelf_2). shelf_accepts(standard, shelf_3).
shelf_accepts(standard, shelf_4). shelf_accepts(standard, shelf_6).
shelf_accepts(standard, shelf_7). shelf_accepts(standard, shelf_9).
shelf_accepts(fragile,  shelf_2). shelf_accepts(fragile,  shelf_3).
shelf_accepts(fragile,  shelf_4). shelf_accepts(fragile,  shelf_6).
shelf_accepts(fragile,  shelf_7). shelf_accepts(fragile,  shelf_9).

robot_shelf_priority(robot_light,  [shelf_2, shelf_3, shelf_4, shelf_6, shelf_7, shelf_9]).
robot_shelf_priority(robot_medium, [shelf_6, shelf_7, shelf_2, shelf_3, shelf_4, shelf_9]).
robot_shelf_priority(robot_heavy,  [shelf_9, shelf_6, shelf_7, shelf_2, shelf_3, shelf_4]).
robot_shelf_priority(robot_heavy2, [shelf_9, shelf_6, shelf_7, shelf_2, shelf_3, shelf_4]).

/* ----------------------------------------------------------------------------
 *  GRUPOS DE TIPO para el ciclo de salida.
 *    standard y fragile comparten shelves → mismo grupo "normal".
 *    urgent va aparte.
 *  Todo el mecanismo de bloqueo/exit opera sobre grupos, no sobre tipos
 *  individuales. La regla blocked_type/1 traduce tipo→grupo para que los
 *  planes que comprueban "tipo bloqueado" sigan funcionando.
 * -------------------------------------------------------------------------- */
type_group(standard, normal).
type_group(fragile,  normal).
type_group(urgent,   urgent).

group_types(normal, [standard, fragile]).
group_types(urgent, [urgent]).

blocked_type(Type) :- type_group(Type, G) & blocked_group(G).

!start.

+!start <-
    .print("Scheduler online. Vigilando accesibilidad + informando ubicaciones.").

/* ============================================================================
 * ENTRADA DE CONTENEDORES
 *   - nuevo contenedor → revisar accesibilidad + pedir info al entorno
 *   - info llega → cachear + anunciar a robots (si el tipo no está bloqueado)
 * ============================================================================ */

+new_container(CId) <-
    .print("Scheduler: nuevo contenedor ", CId, ". Revisando accesibilidad...");
    !check_all_packages;
    get_container_info(CId).

+container_info(CId, W, H, Weight, Type) <-
    V = W * H;
    .abolish(package_info(CId, _, _, _));
    +package_info(CId, Weight, V, Type);
    .send(supervisor, tell, package_arrived(CId, Weight, V, Type));
    !announce_if_allowed(CId, W, H, Weight, Type);
    -container_info(CId, W, H, Weight, Type).

// Tipo bloqueado → encolamos y anunciaremos cuando vuelva el espacio
+!announce_if_allowed(CId, W, H, Weight, Type) : blocked_type(Type) <-
    +pending_announce(CId, W, H, Weight, Type);
    .print("Scheduler: ", CId, " (tipo ", Type, ") en espera — sin espacio").

+!announce_if_allowed(CId, W, H, Weight, Type) <-
    .print("Scheduler: anuncio ", CId, " a robots (tipo=", Type, ", w=", Weight, ", v=", W*H, ")");
    .send(robot_light,   tell, container_available(CId, W, H, Weight, Type));
    .send(robot_medium,  tell, container_available(CId, W, H, Weight, Type));
    .send(robot_heavy,   tell, container_available(CId, W, H, Weight, Type)).

/* ============================================================================
 * CONSULTAS DE LOS ROBOTS
 *   Un robot pregunta por la ubicación actual del contenedor antes de ir a
 *   recogerlo. El entorno mantiene container_at(CId,X,Y) como percept en el
 *   scheduler; aquí solo leemos y respondemos.
 * ============================================================================ */

+!provide_location(CId, Requester) : container_at(CId, X, Y) <-
    .send(Requester, tell, container_location(CId, X, Y)).

+!provide_location(CId, Requester) <-
    .print("Scheduler: sin ubicación para ", CId, ", informo not_found a ", Requester);
    .send(Requester, tell, container_location(CId, none, none)).

/* ============================================================================
 * OCUPACIÓN DE ESTANTERÍAS (sólo informativo — la decisión la hace el supervisor)
 * ============================================================================ */
+shelf_full(Shelf)[source(supervisor)] <-
    .print("Scheduler: ", Shelf, " marcada como ocupada por supervisor");
    -shelf_full(Shelf)[source(supervisor)].

+shelf_free(Shelf)[source(supervisor)] <-
    .print("Scheduler: ", Shelf, " vuelve a estar libre (supervisor)");
    -shelf_free(Shelf)[source(supervisor)].

/* ============================================================================
 * SUGERENCIA DE ESTANTERÍA   (protocolo scheduler ↔ supervisor)
 *
 *  Un robot pide shelf para CId (tipo Type) estando en (RX,RY). El scheduler
 *  NO decide qué estantería tiene espacio — sólo conoce la LISTA DE PRIORIDAD
 *  del robot. Construye una lista ordenada de candidatos y se la pasa al
 *  supervisor, que es quien tiene el estado real de ocupación y escoge la
 *  primera con capacidad. La respuesta la manda el supervisor directo al robot.
 *
 *  Orden de candidatos que construye el scheduler:
 *    - urgent     → shelves urgent ordenadas por distancia Manhattan al robot
 *    - otros tipos con lista personal (robot_shelf_priority):
 *         (Prio ∩ shelf_accepts(Type))  ++  (resto de shelf_accepts(Type))
 *    - otros tipos sin lista personal:
 *         cualquier shelf que acepte Type
 * ============================================================================ */

+!suggest_shelf(CId, Type, RX, RY, Requester) <-
    !build_shelf_candidates(Requester, Type, RX, RY, Cands);
    if (Cands == []) {
        .print("Scheduler: sin candidatos para ", CId, " (tipo ", Type, ") → none a ", Requester);
        .send(Requester, tell, shelf_suggestion(CId, none))
    } else {
        !package_wv(CId, Weight, V);
        .print("Scheduler: candidatos ", Cands, " para ", CId, " (", Requester, ") → supervisor");
        .send(supervisor, achieve,
              pick_first_free(CId, Weight, V, Cands, Requester))
    }.

/* Peso/volumen cacheados si los conocemos; 0/0 si no (el supervisor igual
 * comprueba su shelf_usage para ver si queda capacidad nominal). */
+!package_wv(CId, Weight, V) : package_info(CId, Weight, V, _) <- true.
+!package_wv(_, 0, 0).

/* --- URGENTES: shelves urgent ordenadas por distancia --------------------- */
+!build_shelf_candidates(_, urgent, RX, RY, Cands) <-
    .findall(s(S, D),
             (shelf_accepts(urgent, S) & shelf_location(S, SX, SY) &
              D = math.abs(SX - RX) + math.abs(SY - RY)),
             Raw);
    !sort_by_dist(Raw, Sorted);
    !project_shelves(Sorted, Cands).

/* --- NO URGENTES con lista de prioridad del robot ------------------------- */
+!build_shelf_candidates(Robot, Type, _, _, Cands) :
        robot_shelf_priority(Robot, Prio) <-
    !filter_accepts(Prio, Type, Filtered);
    .findall(S,
             (shelf_accepts(Type, S) & not .member(S, Filtered)),
             Extra);
    .concat(Filtered, Extra, Cands).

/* --- Sin lista de prioridad: todas las que aceptan Type ------------------- */
+!build_shelf_candidates(_, Type, _, _, Cands) <-
    .findall(S, shelf_accepts(Type, S), Cands).

+!filter_accepts([], _, []).
+!filter_accepts([S | Rest], Type, [S | Out]) :
        shelf_accepts(Type, S) <-
    !filter_accepts(Rest, Type, Out).
+!filter_accepts([_ | Rest], Type, Out) <-
    !filter_accepts(Rest, Type, Out).

/* Sort ascendente por D sobre lista de s(S, D). Selection-sort simple. */
+!sort_by_dist([], []).
+!sort_by_dist(L, [s(BS, BD) | Rest]) <-
    !min_pair(L, s(none, 99999), s(BS, BD));
    .delete(s(BS, BD), L, Without);
    !sort_by_dist(Without, Rest).

+!min_pair([], Cur, Cur).
+!min_pair([s(S, D) | R], s(_, CD), Best) : D < CD <-
    !min_pair(R, s(S, D), Best).
+!min_pair([_ | R], Cur, Best) <-
    !min_pair(R, Cur, Best).

+!project_shelves([], []).
+!project_shelves([s(S, _) | R], [S | Out]) <-
    !project_shelves(R, Out).

/* ============================================================================
 * REGISTROS DE ALMACENAMIENTO / SALIDA
 *   - guardado(CId, Shelf)   → reenvía al supervisor con peso/vol/tipo
 *   - container_exited       → lo percibe del entorno al hacer drop_at_exit
 * ============================================================================ */

+guardado(CId, Shelf)[source(R)] : package_info(CId, Weight, V, Type) <-
    .print("Scheduler: ", R, " depositó ", CId, " en ", Shelf);
    .send(supervisor, tell, package_stored(CId, Shelf, Weight, V, Type));
    -guardado(CId, Shelf)[source(R)].

+guardado(CId, Shelf)[source(R)] <-
    .print("Scheduler: ", R, " depositó ", CId, " en ", Shelf, " (sin info cacheada)");
    .send(supervisor, tell, package_stored(CId, Shelf, 0, 0, unknown));
    -guardado(CId, Shelf)[source(R)].

/* Los planes +container_exited/4 viven en la sección del ciclo de salida
 * (más abajo). No se declara nada genérico aquí para que los guards de
 * fase (stored_phase / unstorable_phase) tengan prioridad. */

/* ============================================================================
 * COMPROBACIÓN DE ACCESIBILIDAD (sin cambios respecto a la versión anterior)
 * ============================================================================ */

+!check_all_packages <-
    .findall(ca(Id, X, Y), container_at(Id, X, Y), L);
    !process_each(L).

+!process_each([]).
+!process_each([ca(Id, X, Y) | Rest]) <-
    !ensure_accessible(Id, X, Y);
    !process_each(Rest).

+!ensure_accessible(CId, X, Y) <-
    !is_accessible(X, Y, R);
    if (R \== true) {
        .print("Scheduler: ", CId, " en (", X, ",", Y, ") NO accesible. Reubicando...");
        !relocate_safely(CId)
    }.

+!relocate_safely(CId) <-
    .findall(pos(DX, DY),
             (classification_cell(DX, DY) & not occupied(DX, DY)),
             Candidates);
    !pick_accessible_candidate(Candidates, Dest);
    if (Dest == none) {
        .print("Scheduler: sin celda de clasificación accesible para ", CId)
    } else {
        Dest = pos(TX, TY);
        .print("Scheduler: reubicando ", CId, " → (", TX, ",", TY, ")");
        relocate_container(CId, TX, TY)
    }.

+!pick_accessible_candidate([], none).
+!pick_accessible_candidate([pos(X, Y) | Rest], Chosen) <-
    !is_accessible(X, Y, R);
    if (R == true) {
        Chosen = pos(X, Y)
    } else {
        !pick_accessible_candidate(Rest, Chosen)
    }.

+!is_accessible(X, Y, R) <-
    !bfs([pos(X, Y)], [pos(X, Y)], R).

+!bfs([], _, false).
+!bfs([pos(X, Y) | _], _, true) : empty_exit(X, Y).
+!bfs([pos(X, Y) | Rest], Visited, R) <-
    XP = X + 1; XM = X - 1; YP = Y + 1; YM = Y - 1;
    Ns = [pos(XP, Y), pos(XM, Y), pos(X, YP), pos(X, YM)];
    !filter_passable(Ns, Visited, NewOnes);
    .concat(Rest, NewOnes, NextQueue);
    .concat(Visited, NewOnes, NewVisited);
    !bfs(NextQueue, NewVisited, R).

+!filter_passable([], _, []).
+!filter_passable([pos(X, Y) | Rest], Visited, Out) :
        .member(pos(X, Y), Visited) <-
    !filter_passable(Rest, Visited, Out).
+!filter_passable([pos(X, Y) | Rest], Visited, [pos(X, Y) | Out]) :
        empty_exit(X, Y) <-
    !filter_passable(Rest, Visited, Out).
+!filter_passable([pos(X, Y) | Rest], Visited, [pos(X, Y) | Out]) :
        zone_cell(X, Y) & not occupied(X, Y) <-
    !filter_passable(Rest, Visited, Out).
+!filter_passable([_ | Rest], Visited, Out) <-
    !filter_passable(Rest, Visited, Out).

/* ============================================================================
 *  CICLO DE SALIDA POR DEADLINES
 *
 *  Disparador: supervisor avisa no_space(Type). Ese instante es T0.
 *    - se bloquea la generación de TODOS los tipos (para no solapar fases).
 *    - se arranca un ciclo de salida que consta de DOS deadlines NO solapados:
 *        · Deadline corto [T0, T0+ΔT]          → sólo URGENTES
 *        · Deadline largo [T0+ΔT, T0+3·ΔT]     → sólo NO-URGENTES
 *    - al vencer el deadline largo termina el ciclo y se reanuda la generación.
 *
 *  ΔT = 20 s. Se eligió 20 s como compromiso entre (a) tiempo realista para que
 *  los robots lentos puedan completar al menos una entrega de su deadline
 *  (movimiento medio ~10-15 celdas a 100-500 ms/celda, cf. timePerMove de cada
 *  robot) y (b) no alargar el experimento en exceso; 3·ΔT = 60 s deja margen
 *  para vaciar varios paquetes no-urgentes con 4 robots trabajando en paralelo.
 *
 *  Protocolo de salida (robots autónomos, SIN asignación explícita):
 *    1. Scheduler construye dos listas cuando empieza cada deadline:
 *         · stored en shelves "propias" del deadline (S1/S5/S8 | resto)
 *         · unstorable acumulados del grupo correspondiente
 *    2. Para cada contenedor, envía a todos los robots:
 *         tell exit_item(CId, Loc, Weight, V, Type, Kind)
 *       donde Loc = at_shelf(S) | at_entry(X,Y), Kind = short | long.
 *    3. Robots ven los exit_item, deciden cuál coger (capacidad + distancia).
 *       Para evitar colisiones, piden claim al scheduler antes de retirar:
 *         achieve claim_exit(CId, Me)   → claim_result(CId, granted|denied)
 *       Al conceder claim, scheduler broadcasts exit_taken(CId) para que los
 *       demás abolishen su copia local del exit_item.
 *    4. Robot ejecuta (retrieve/pickup + drop_at_exit) y avisa:
 *         tell exit_done(CId, Type)  →  el scheduler cuenta y avisa a transport.
 *    5. Al vencer el deadline, scheduler abolish los exit_item restantes en
 *       todos los robots; el siguiente deadline los reemplaza.
 *
 *  Transport: agente externo que "recoge" los contenedores salidos en cada
 *  deadline (load_start / container_shipped / load_end).
 * ============================================================================ */

delta_t(20000).  // ΔT en milisegundos

unstorable_threshold(3).

/* Registro de unstorable (sigue siendo por GRUPO para que al disparar el ciclo
 * tengamos la lista de pendientes del grupo adecuado). */
+unstorable(CId, Type)[source(_)] <-
    -unstorable(CId, Type)[source(_)];
    ?type_group(Type, Group);
    !record_unstorable(CId, Group).

+!record_unstorable(CId, Group) :
        unstorable_pending(Group, L) & .member(CId, L) <-
    true.

+!record_unstorable(CId, Group) :
        unstorable_pending(Group, L) <-
    -+unstorable_pending(Group, [CId | L]);
    .length([CId | L], N);
    .print("Scheduler: unstorable ", CId, " (grupo ", Group, "). Pendientes=", N);
    !check_unstorable_threshold(Group, N).

+!record_unstorable(CId, Group) <-
    +unstorable_pending(Group, [CId]);
    .print("Scheduler: unstorable ", CId, " (grupo ", Group, "). Pendientes=1");
    !check_unstorable_threshold(Group, 1).

+!check_unstorable_threshold(Group, N) :
        unstorable_threshold(T) & N >= T & not exit_cycle_active <-
    .print("Scheduler: umbral unstorable alcanzado para grupo ", Group, " — disparo ciclo");
    !begin_exit_cycle(Group).
+!check_unstorable_threshold(_, _).

/* Disparador desde supervisor: 70 % de un tipo */
+no_space(Type)[source(supervisor)] :
        type_group(Type, Group) & not exit_cycle_active <-
    .print("Scheduler: supervisor avisa no_space(", Type, ") — grupo ", Group);
    -no_space(Type)[source(supervisor)];
    !begin_exit_cycle(Group).

+no_space(Type)[source(supervisor)] <-
    -no_space(Type)[source(supervisor)].

/* ---------------------------------------------------------------------------
 *  Arranque del ciclo (T0) — bloquea generación y lanza los dos deadlines
 * ------------------------------------------------------------------------- */
+!begin_exit_cycle(TriggerGroup) <-
    +exit_cycle_active;
    +trigger_group(TriggerGroup);
    !block_all_types;
    .send(supervisor, tell, exit_cycle_started);
    .print("Scheduler: T0 — INICIO ciclo de salida (disparado por grupo ", TriggerGroup, ")");
    .time(HH, MM, SS);
    .print("EVENT | time=", HH, ":", MM, ":", SS,
           " | agent=scheduler | type=output_phase_started | data=", TriggerGroup);
    !run_deadline(short, [urgent],            1);   // ΔT·1
    !run_deadline(long,  [standard, fragile], 2);   // ΔT·2 → [T0+ΔT, T0+3ΔT]
    !end_exit_cycle.

+!block_all_types <-
    block_generation(urgent);
    block_generation(standard);
    block_generation(fragile);
    +blocked_group(urgent);
    +blocked_group(normal).

+!unblock_all_types <-
    unblock_generation(urgent);
    unblock_generation(standard);
    unblock_generation(fragile);
    -blocked_group(urgent);
    -blocked_group(normal).

/* ---------------------------------------------------------------------------
 *  Un deadline: arma listas, publica, espera Duration ms, limpia.
 * ------------------------------------------------------------------------- */
+!run_deadline(Kind, Types, Factor) :
        delta_t(DT) <-
    Duration = DT * Factor;
    .print("Scheduler: DEADLINE ", Kind, " activo — tipos=", Types, ", duración=", Duration, "ms");
    +active_deadline(Kind);
    +deadline_shipped_count(Kind, 0);
    .send(transport, tell, load_start(Kind, Types));
    !broadcast_deadline_start(Kind);
    !publish_stored_items(Types, Kind);
    !publish_unstorable_items(Types, Kind);
    .wait(Duration);
    !close_deadline(Kind).

+!close_deadline(Kind) <-
    .print("Scheduler: DEADLINE ", Kind, " cerrado");
    -active_deadline(Kind);
    ?deadline_shipped_count(Kind, N);
    -deadline_shipped_count(Kind, _);
    .send(transport, tell, load_end(Kind, N));
    !broadcast_deadline_end(Kind);
    !abolish_all_exit_items(Kind).

/* Publica la lista de stored pidiéndosela al supervisor */
+!publish_stored_items(Types, Kind) <-
    .abolish(stored_list_response(_, _));
    .send(supervisor, achieve, list_stored(Types, Kind));
    .wait({+stored_list_response(Kind, _)}, 3000, _);
    if (stored_list_response(Kind, L)) {
        .abolish(stored_list_response(Kind, _));
        !publish_stored_list(L, Kind)
    } else {
        .print("Scheduler: timeout esperando stored_list de ", Kind)
    }.

+!publish_stored_list([], _).
+!publish_stored_list([s(CId, Shelf, W, V, Type) | Rest], Kind) <-
    !publish_exit_item(CId, at_shelf(Shelf), W, V, Type, Kind);
    !publish_stored_list(Rest, Kind).

/* Publica los unstorable de los tipos del deadline que aún están en la entrada */
+!publish_unstorable_items([], _).
+!publish_unstorable_items([T | Rest], Kind) <-
    ?type_group(T, G);
    !publish_unstorable_for_group(G, Kind);
    !publish_unstorable_items(Rest, Kind).

+!publish_unstorable_for_group(G, Kind) :
        unstorable_pending(G, L) <-
    !publish_unstorable_list(L, G, Kind).
+!publish_unstorable_for_group(_, _).

+!publish_unstorable_list([], _, _).
+!publish_unstorable_list([CId | Rest], G, Kind) :
        container_at(CId, X, Y) & package_info(CId, W, V, Type) <-
    !publish_exit_item(CId, at_entry(X, Y), W, V, Type, Kind);
    !publish_unstorable_list(Rest, G, Kind).
+!publish_unstorable_list([_ | Rest], G, Kind) <-
    !publish_unstorable_list(Rest, G, Kind).

/* Registra el exit_item local y lo envía a los cuatro robots */
+!publish_exit_item(CId, Loc, W, V, Type, Kind) <-
    +pending_exit(CId, Loc, W, V, Type, Kind);
    .send(robot_light,  tell, exit_item(CId, Loc, W, V, Type, Kind));
    .send(robot_medium, tell, exit_item(CId, Loc, W, V, Type, Kind));
    .send(robot_heavy,  tell, exit_item(CId, Loc, W, V, Type, Kind));
    .send(robot_heavy2, tell, exit_item(CId, Loc, W, V, Type, Kind)).

+!broadcast_deadline_start(Kind) <-
    .broadcast(tell, active_deadline(Kind)).

+!broadcast_deadline_end(Kind) <-
    .broadcast(untell, active_deadline(Kind)).

/* Al cerrar un deadline, retira los exit_item no consumidos de todos los robots
 * y limpia estado local. */
+!abolish_all_exit_items(Kind) <-
    .findall(e(CId, Loc, W, V, Type),
             pending_exit(CId, Loc, W, V, Type, Kind),
             Pend);
    !abolish_on_robots(Pend, Kind);
    .abolish(pending_exit(_, _, _, _, _, Kind));
    .abolish(claimed(_)).

+!abolish_on_robots([], _).
+!abolish_on_robots([e(CId, Loc, W, V, Type) | Rest], Kind) <-
    .broadcast(untell, exit_item(CId, Loc, W, V, Type, Kind));
    !abolish_on_robots(Rest, Kind).

/* ---------------------------------------------------------------------------
 *  CLAIM: un robot pide permiso para llevarse CId (fuente = el propio robot)
 * ------------------------------------------------------------------------- */
+!claim_exit(CId, Requester)[source(Requester)] :
        pending_exit(CId, _, _, _, _, _) & not claimed(CId) <-
    +claimed(CId);
    .print("Scheduler: claim GRANTED ", CId, " → ", Requester);
    .send(Requester, tell, claim_result(CId, granted));
    .broadcast(tell, exit_taken(CId)).

+!claim_exit(CId, Requester)[source(Requester)] <-
    .print("Scheduler: claim DENIED ", CId, " → ", Requester);
    .send(Requester, tell, claim_result(CId, denied)).

/* Robot completa — avisa a transport, cuenta y limpia unstorable si aplica */
+exit_done(CId, Type)[source(Reporter)] <-
    -exit_done(CId, Type)[source(Reporter)];
    .send(transport, tell, container_shipped(CId, Type));
    !remove_from_unstorable(CId);
    !bump_shipped_count;
    -pending_exit(CId, _, _, _, _, _);
    -claimed(CId);
    .broadcast(untell, exit_taken(CId)).

+!bump_shipped_count : active_deadline(K) & deadline_shipped_count(K, N) <-
    -+deadline_shipped_count(K, N + 1).
+!bump_shipped_count.

+!remove_from_unstorable(CId) <-
    .findall(gl(G, L), unstorable_pending(G, L), GLs);
    !remove_cid_from_groups(GLs, CId).

+!remove_cid_from_groups([], _).
+!remove_cid_from_groups([gl(G, L) | Rest], CId) :
        .member(CId, L) <-
    .delete(CId, L, NewL);
    -+unstorable_pending(G, NewL);
    !remove_cid_from_groups(Rest, CId).
+!remove_cid_from_groups([_ | Rest], CId) <-
    !remove_cid_from_groups(Rest, CId).

/* Cuando el env emite container_exited sólo lo usamos para limpiar la caché
 * local (package_info). El progreso del ciclo está marcado por exit_done. */
+container_exited(CId, Type, Weight, V) <-
    .abolish(package_info(CId, _, _, _));
    -container_exited(CId, Type, Weight, V).

/* ---------------------------------------------------------------------------
 *  FIN DEL CICLO — reanuda generación + flush de pending_announce
 * ------------------------------------------------------------------------- */
+!end_exit_cycle <-
    -exit_cycle_active;
    -trigger_group(_);
    .abolish(unstorable_pending(_, _));
    !unblock_all_types;
    .send(supervisor, tell, exit_cycle_ended);
    .print("Scheduler: FIN ciclo de salida — reanudo generación normal");
    !flush_all_pending_announce.

+!flush_all_pending_announce <-
    .findall(p(C, W, H, Wt, Ty), pending_announce(C, W, H, Wt, Ty), All);
    !replay_pending_list(All).

+!replay_pending_list([]).
+!replay_pending_list([p(C, W, H, Wt, Ty) | Rest]) <-
    -pending_announce(C, W, H, Wt, Ty);
    !announce_if_allowed(C, W, H, Wt, Ty);
    !replay_pending_list(Rest).
