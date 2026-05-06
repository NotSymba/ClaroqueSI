/*******************************************************************************
 * SCHEDULER - Agente planificador
 *
 * Responsabilidades:
 *   1. Garantizar accesibilidad de los paquetes en la zona de entrada /
 *      clasificación (reubica si algún paquete queda atrapado).
 *   2. Punto central de información: responde a consultas de los robots sobre
 *      la ubicación de los contenedores.
 *   3. Anuncia nuevos contenedores a los robots. La ELECCIÓN de estantería
 *      la hacen los robots de forma autónoma (protocolo peer-to-peer con
 *      pre-reservas, ver work.asl); el scheduler NO sugiere ni asigna shelf.
 *      Si un robot no encuentra shelf con hueco (contando reservas activas)
 *      nos envía tell unstorable(CId, Tags) y contamos para el ciclo.
 *   4. Recibe el aviso del supervisor cuando no queda espacio para un grupo
 *      (no_space(Group) al 70 %) o acumulamos unstorable_threshold paquetes
 *      sin almacenar: dispara el ciclo de salida del grupo afectado y bloquea
 *      la generación de ese grupo hasta que termina el deadline.
 *
 * MODELO DE ETIQUETAS (tags):
 *   El "tipo" de un paquete es una LISTA de etiquetas Jason. Posibles combos:
 *     [standard]            paquete normal
 *     [urgent]              urgente puro
 *     [fragile]             frágil puro
 *     [urgent, fragile]     combo (sale en deadline corto Y el robot va lento)
 *
 *   El grupo de salida lo determina la presencia de la etiqueta `urgent`:
 *     tags_group(Tags, urgent) :- .member(urgent, Tags).
 *     tags_group(Tags, normal) :- not .member(urgent, Tags).
 *
 *   Esto consolida los antiguos type_group(standard, normal) /
 *   type_group(fragile, normal) / type_group(urgent, urgent).
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
 *  ESTANTERÍAS: ubicación conocida por el scheduler para el ciclo de salida
 *  (el scheduler necesita la posición de cada shelf para decidir al construir
 *  exit_item). La elección real de shelf en la ENTRADA ya NO vive aquí: cada
 *  robot lleva su propia copia del estado (shelf_usage_local + reservas) y
 *  elige localmente siguiendo su robot_shelf_priority en work.asl.
 * -------------------------------------------------------------------------- */
shelf_location(shelf_1, 10,  2). shelf_location(shelf_2, 12,  2).
shelf_location(shelf_3, 14,  2). shelf_location(shelf_4, 16,  2).
shelf_location(shelf_5, 10,  6). shelf_location(shelf_6, 13,  6).
shelf_location(shelf_7, 16,  6).
shelf_location(shelf_8, 10, 10). shelf_location(shelf_9, 14, 10).

/* ----------------------------------------------------------------------------
 *  GRUPOS DE TAGS para el ciclo de salida.
 *    Si la lista de etiquetas contiene `urgent` → grupo `urgent` (deadline
 *    CORTO, shelves S1/S5/S8). Si NO contiene `urgent` → grupo `normal`
 *    (deadline LARGO, resto de shelves).
 *    `fragile` es ortogonal: indica solo que el robot debe ir más despacio
 *    durante el transporte (mov.asl, carrying_fragile).
 *
 *    blocked_tags(Tags) traduce tags→grupo para que los planes que comprueban
 *    "tipo bloqueado" sigan funcionando.
 * -------------------------------------------------------------------------- */
tags_group(Tags, urgent) :- .member(urgent, Tags).
tags_group(Tags, normal) :- not .member(urgent, Tags).

blocked_tags(Tags) :- tags_group(Tags, G) & blocked_group(G).

!start.

+!start <-
    .print("Scheduler online. Vigilando accesibilidad + informando ubicaciones.").

/* ============================================================================
 * ENTRADA DE CONTENEDORES
 *   - nuevo contenedor → revisar accesibilidad + pedir info al entorno
 *   - info llega → cachear + anunciar a robots (si el grupo no está bloqueado)
 * ============================================================================ */

+new_container(CId) <-
    .print("Scheduler: nuevo contenedor ", CId, ". Revisando accesibilidad...");
    !check_all_packages;
    get_container_info(CId).

+container_info(CId, W, H, Weight, Tags) <-
    V = W * H;
    .abolish(package_info(CId, _, _, _));
    +package_info(CId, Weight, V, Tags);
    .send(supervisor, tell, package_arrived(CId, Weight, V, Tags));
    !announce_if_allowed(CId, W, H, Weight, Tags);
    -container_info(CId, W, H, Weight, Tags).

// Grupo bloqueado → encolamos y anunciaremos cuando vuelva el espacio
+!announce_if_allowed(CId, W, H, Weight, Tags) : blocked_tags(Tags) <-
    +pending_announce(CId, W, H, Weight, Tags);
    .print("Scheduler: ", CId, " (tags ", Tags, ") en espera — sin espacio").

+!announce_if_allowed(CId, W, H, Weight, Tags) <-
    .print("Scheduler: anuncio ", CId, " a robots (tags=", Tags, ", w=", Weight, ", v=", W*H, ")");
    .send(robot_light,   tell, container_available(CId, W, H, Weight, Tags));
    .send(robot_medium,  tell, container_available(CId, W, H, Weight, Tags));
    .send(robot_heavy,   tell, container_available(CId, W, H, Weight, Tags));
    .send(robot_heavy2,  tell, container_available(CId, W, H, Weight, Tags)).

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
 * REGISTROS DE ALMACENAMIENTO / SALIDA
 *   - guardado(CId, Shelf)   → reenvía al supervisor con peso/vol/tags
 *   - container_exited       → lo percibe del entorno al hacer drop_at_exit
 * ============================================================================ */

/* Versión nueva con W,V incluidos por el robot. Se usa para el package_stored
 * al supervisor con valores ciertos, sin depender de package_info (que podría
 * no estar al recibir el guardado por ventanas de carrera con container_exited
 * o container_destroyed previos). Las Tags se intentan resolver desde el caché
 * pero si no están, se manda [unknown] (no afecta a shelf_usage del supervisor). */
+guardado(CId, Shelf, W, V)[source(R)] : package_info(CId, _, _, Tags) <-
    .print("Scheduler: ", R, " depositó ", CId, " en ", Shelf);
    .send(supervisor, tell, package_stored(CId, Shelf, W, V, Tags));
    .abolish(guardado(CId, Shelf, W, V)[source(R)]);
    +log_pkg(R, CId, Shelf).

+guardado(CId, Shelf, W, V)[source(R)] <-
    .print("Scheduler: ", R, " depositó ", CId, " en ", Shelf, " (tags desconocidos, peso/vol del robot)");
    .send(supervisor, tell, package_stored(CId, Shelf, W, V, [unknown]));
    .abolish(guardado(CId, Shelf, W, V)[source(R)]);
    +log_pkg(R, CId, Shelf).

/* Compatibilidad: ruta legacy del caso patológico de finish_task (sin reserva
 * ni pending_drop). No tenemos W,V; usamos package_info si está, y si no hay
 * absolutamente nada, registramos el guardado solo a efectos de log_pkg sin
 * tocar shelf_usage del supervisor (no inflar con 0,0 que luego un retrieve
 * descontaría como negativo). */
+guardado(CId, Shelf)[source(R)] : package_info(CId, Weight, V, Tags) <-
    .print("Scheduler: ", R, " depositó ", CId, " en ", Shelf, " (legacy, info cacheada)");
    .send(supervisor, tell, package_stored(CId, Shelf, Weight, V, Tags));
    .abolish(guardado(CId, Shelf)[source(R)]);
    +log_pkg(R, CId, Shelf).

+guardado(CId, Shelf)[source(R)] <-
    .print("Scheduler: AVISO guardado(", CId, ",", Shelf, ") legacy SIN info — solo log_pkg, no actualizo shelf_usage");
    .abolish(guardado(CId, Shelf)[source(R)]);
    +log_pkg(R, CId, Shelf).

/* Los planes +container_exited/4 viven en la sección del ciclo de salida
 * (más abajo). No se declara nada genérico aquí para que los guards de
 * fase (stored_phase / unstorable_phase) tengan prioridad. */

/* ----------------------------------------------------------------------------
 *  CONTENEDOR APLASTADO POR UN ROBOT (splash). El env destruye el paquete y
 *  notifica a todos los agentes para que purguen referencias.
 * -------------------------------------------------------------------------- */
+container_destroyed(CId, Tags) <-
    .print("Scheduler: contenedor ", CId, " (tags ", Tags, ") destruido — limpio referencias");
    .abolish(package_info(CId, _, _, _));
    .abolish(pending_announce(CId, _, _, _, _));
    .abolish(claimed(CId));
    .abolish(pending_exit(CId, _, _, _, _, _));
    .abolish(container_at(CId, _, _));
    !remove_from_unstorable(CId);
    .broadcast(untell, exit_item(CId, _, _, _, _, _));
    .broadcast(untell, container_available(CId, _, _, _, _));
    .broadcast(untell, exit_taken(CId));
    -container_destroyed(CId, Tags).

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
 *  Disparador: supervisor avisa no_space(Group). Ese instante es T0.
 *    - se bloquea la generación del grupo afectado en el entorno.
 *    - Deadline corto [T0, T0+ΔT]   → paquetes con etiqueta `urgent`
 *      (incluye combos urgent+fragile)
 *    - Deadline largo [T0+ΔT, T0+3·ΔT] → paquetes SIN etiqueta `urgent`
 *      (standard puro y fragile puro)
 *    - al vencer el deadline largo termina el ciclo y se reanuda la generación.
 *
 *  ΔT = 30 s.
 *
 *  Protocolo de salida (robots autónomos, SIN asignación explícita):
 *    1. Scheduler construye listas cuando empieza cada deadline:
 *         · stored en shelves del grupo (S1/S5/S8 para urgent | resto para normal)
 *         · unstorable acumulados del grupo correspondiente
 *    2. Para cada contenedor, envía a todos los robots:
 *         tell exit_item(CId, Loc, Weight, V, Tags, Kind)
 *       donde Loc = at_shelf(S) | at_entry(X,Y), Kind = short | long.
 *    3. Robots ven los exit_item, deciden cuál coger (capacidad + distancia).
 *       Para evitar colisiones, piden claim al scheduler antes de retirar.
 *    4. Robot ejecuta (retrieve/pickup + drop_at_exit) y avisa:
 *         tell exit_done(CId, Tags) → el scheduler cuenta y avisa a transport.
 * ============================================================================ */

delta_t(30000).  // ΔT en milisegundos

unstorable_threshold(3).

pending_queue([]).

/* Registro de unstorable (sigue siendo por GRUPO para que al disparar el ciclo
 * tengamos la lista de pendientes del grupo adecuado). */
+unstorable(CId, Tags)[source(_)] <-
    .abolish(unstorable(CId, Tags)[source(_)]);
    ?tags_group(Tags, Group);
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
+!check_unstorable_threshold(Group, N) :
        unstorable_threshold(T) & N >= T & exit_cycle_active <-
    .print("Scheduler: umbral unstorable alcanzado para grupo ", Group,
           " durante ciclo activo — encolando");
    !enqueue_pending(Group).
+!check_unstorable_threshold(_, _).

/* ---------------------------------------------------------------------------
 *  COLA DE DEADLINES PENDIENTES (FIFO + dedup)
 * ------------------------------------------------------------------------- */
+!enqueue_pending(Group) : trigger_group(Group) <-
    .print("Scheduler: ", Group, " es ya el deadline en curso — descarto trigger duplicado").

+!enqueue_pending(Group) : pending_queue(Q) & .member(Group, Q) <-
    .print("Scheduler: ", Group, " ya estaba en la cola pendiente — no duplico").

+!enqueue_pending(Group) : pending_queue(Q) <-
    .concat(Q, [Group], NewQ);
    -+pending_queue(NewQ);
    .print("Scheduler: encolado deadline ", Group, " (cola pendiente = ", NewQ, ")").

/* Disparo forzado desde un robot: el robot pasa Tags (no Type). */
+force_exit_cycle(Tags)[source(_)] :
        tags_group(Tags, Group) & not exit_cycle_active <-
    .abolish(force_exit_cycle(_)[source(_)]);
    .print("Scheduler: ciclo de salida forzado por robot (grupo ", Group, ") — caso límite");
    !begin_exit_cycle(Group).

+force_exit_cycle(Tags)[source(_)] :
        tags_group(Tags, Group) & exit_cycle_active <-
    .abolish(force_exit_cycle(_)[source(_)]);
    .print("Scheduler: force_exit_cycle(", Tags, ") durante ciclo activo — encolando ", Group);
    !enqueue_pending(Group).

+force_exit_cycle(Tags)[source(_)] <-
    .abolish(force_exit_cycle(Tags)[source(_)]).

/* Disparador desde supervisor: 70 % de un grupo. El supervisor manda
 * directamente el GRUPO (urgent | normal) y no el tipo individual. */
+no_space(Group)[source(supervisor)] : not exit_cycle_active <-
    .print("Scheduler: supervisor avisa no_space(", Group, ")");
    -no_space(Group)[source(supervisor)];
    !begin_exit_cycle(Group).

+no_space(Group)[source(supervisor)] : exit_cycle_active <-
    .print("Scheduler: supervisor avisa no_space(", Group,
           ") durante ciclo activo — encolando");
    -no_space(Group)[source(supervisor)];
    !enqueue_pending(Group).

+no_space(Group)[source(supervisor)] <-
    -no_space(Group)[source(supervisor)].

/* ---------------------------------------------------------------------------
 *  Arranque del ciclo (T0)
 * ------------------------------------------------------------------------- */
+!begin_exit_cycle(TriggerGroup) <-
    +exit_cycle_active;
    !run_one_deadline(TriggerGroup).

+!run_one_deadline(Group) <-
    +trigger_group(Group);
    !block_group(Group);
    .send(supervisor, tell, exit_cycle_started);
    .print("Scheduler: T0 — INICIO ciclo de salida (grupo=", Group, ")");
    log_event(output_phase_started, Group);
    !run_deadline_for(Group);
    !end_exit_cycle(Group).

/* Dispatch: solo el deadline del grupo disparador. */
+!run_deadline_for(urgent) <- !run_deadline(short, urgent, 1).
+!run_deadline_for(normal) <- !run_deadline(long,  normal, 3).

/* Bloqueo per-grupo: el entorno ahora bloquea por grupo (urgent|normal). */
+!block_group(urgent) <-
    block_generation(urgent);
    +blocked_group(urgent);
    .print("Scheduler: generación URGENT bloqueada (normales siguen fluyendo)").

+!block_group(normal) <-
    block_generation(normal);
    +blocked_group(normal);
    .print("Scheduler: generación NORMAL bloqueada (standard+fragile, urgentes siguen fluyendo)").

+!unblock_group(urgent) <-
    unblock_generation(urgent);
    -blocked_group(urgent);
    .print("Scheduler: generación URGENT reanudada").

+!unblock_group(normal) <-
    unblock_generation(normal);
    -blocked_group(normal);
    .print("Scheduler: generación NORMAL reanudada").

/* ---------------------------------------------------------------------------
 *  Un deadline: arma listas, publica, espera Duration ms, limpia.
 *
 *  Ahora el deadline se identifica por GRUPO (urgent|normal) y el `Types`
 *  que se enviaba a transport/supervisor pasa a ser el grupo.
 * ------------------------------------------------------------------------- */
+!run_deadline(Kind, Group, Factor) :
        delta_t(DT) & trigger_group(_) <-
    Duration = DT * Factor;
    .print("Scheduler: DEADLINE ", Kind, " activo — grupo=", Group, ", duración=", Duration, "ms");
    +active_deadline(Kind);
    +deadline_shipped_count(Kind, 0);
    log_event(deadline_started, Group);
    .send(transport, tell, load_start(Kind, Group));
    // Supervisor arranca su propia vigilancia temporal del deadline.
    .send(supervisor, tell, deadline_started(Kind, Group, Duration));
    !broadcast_deadline_start(Kind);
    !publish_stored_items(Group, Kind);
    !publish_unstorable_items(Group, Kind);
    .wait(Duration);
    !close_deadline(Kind).

+!close_deadline(Kind) :
        trigger_group(Group) <-
    .print("Scheduler: DEADLINE ", Kind, " cerrado");
    -active_deadline(Kind);
    ?deadline_shipped_count(Kind, N);
    -deadline_shipped_count(Kind, _);
    log_event(deadline_ended, Group);
    .send(transport, tell, load_end(Kind, N));
    !broadcast_deadline_end(Kind);
    !abolish_all_exit_items(Kind).

+!close_deadline(Kind) <-
    .print("Scheduler: DEADLINE ", Kind, " cerrado (sin trigger_group disponible)");
    -active_deadline(Kind);
    ?deadline_shipped_count(Kind, N);
    -deadline_shipped_count(Kind, _);
    .send(transport, tell, load_end(Kind, N));
    !broadcast_deadline_end(Kind);
    !abolish_all_exit_items(Kind).

/* Publica la lista de stored pidiéndosela al supervisor por GRUPO. */
+!publish_stored_items(Group, Kind) <-
    .abolish(stored_list_response(_, _));
    .send(supervisor, achieve, list_stored(Group, Kind));
    .wait({+stored_list_response(Kind, _)}, 3000, _);
    if (stored_list_response(Kind, L)) {
        .abolish(stored_list_response(Kind, _));
        !publish_stored_list(L, Kind)
    } else {
        .print("Scheduler: timeout esperando stored_list de ", Kind)
    }.

+!publish_stored_list([], _).
+!publish_stored_list([s(CId, Shelf, W, V, Tags) | Rest], Kind) <-
    !publish_exit_item(CId, at_shelf(Shelf), W, V, Tags, Kind);
    !publish_stored_list(Rest, Kind).

/* Publica los unstorable del grupo + cosecha pending_announce del grupo. */
+!publish_unstorable_items(Group, Kind) <-
    !harvest_pending_announce_for_group(Group);
    !publish_unstorable_for_group(Group, Kind).

+!harvest_pending_announce_for_group(G) <-
    .findall(pa(CId, W, H, Wt, Tags),
             (pending_announce(CId, W, H, Wt, Tags) & tags_group(Tags, G)),
             All);
    !harvest_pa_each(All, G).

+!harvest_pa_each([], _).
+!harvest_pa_each([pa(CId, W, H, Wt, Tags) | Rest], G) <-
    -pending_announce(CId, W, H, Wt, Tags);
    .print("Scheduler: cosecho pending ", CId, " (tags ", Tags, ") → unstorable del grupo ", G);
    !record_unstorable(CId, G);
    !harvest_pa_each(Rest, G).

+!publish_unstorable_for_group(G, Kind) :
        unstorable_pending(G, L) <-
    !publish_unstorable_list(L, G, Kind).
+!publish_unstorable_for_group(_, _).

+!publish_unstorable_list([], _, _).
+!publish_unstorable_list([CId | Rest], G, Kind) :
        container_at(CId, X, Y) & package_info(CId, W, V, Tags) <-
    !publish_exit_item(CId, at_entry(X, Y), W, V, Tags, Kind);
    !publish_unstorable_list(Rest, G, Kind).
+!publish_unstorable_list([_ | Rest], G, Kind) <-
    !publish_unstorable_list(Rest, G, Kind).

/* Registra el exit_item local y lo envía a los cuatro robots */
+!publish_exit_item(CId, Loc, W, V, Tags, Kind) <-
    +pending_exit(CId, Loc, W, V, Tags, Kind);
    .send(robot_light,  tell, exit_item(CId, Loc, W, V, Tags, Kind));
    .send(robot_medium, tell, exit_item(CId, Loc, W, V, Tags, Kind));
    .send(robot_heavy,  tell, exit_item(CId, Loc, W, V, Tags, Kind));
    .send(robot_heavy2, tell, exit_item(CId, Loc, W, V, Tags, Kind)).

+!broadcast_deadline_start(Kind) <-
    .broadcast(tell, active_deadline(Kind)).

+!broadcast_deadline_end(Kind) <-
    .broadcast(untell, active_deadline(Kind)).

/* Al cerrar un deadline, retira los exit_item no consumidos de todos los robots
 * y limpia estado local. */
+!abolish_all_exit_items(Kind) <-
    .findall(e(CId, Loc, W, V, Tags),
             pending_exit(CId, Loc, W, V, Tags, Kind),
             Pend);
    !abolish_on_robots(Pend, Kind);
    .abolish(pending_exit(_, _, _, _, _, Kind));
    .abolish(claimed(_)).

+!abolish_on_robots([], _).
+!abolish_on_robots([e(CId, Loc, W, V, Tags) | Rest], Kind) <-
    .broadcast(untell, exit_item(CId, Loc, W, V, Tags, Kind));
    !abolish_on_robots(Rest, Kind).

/* ---------------------------------------------------------------------------
 *  CLAIM: un robot pide permiso para llevarse CId
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
+exit_done(CId, Tags)[source(Reporter)] <-
    -exit_done(CId, Tags)[source(Reporter)];
    .send(transport, tell, container_shipped(CId, Tags));
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
+container_exited(CId, Tags, Weight, V) <-
    .abolish(package_info(CId, _, _, _));
    -container_exited(CId, Tags, Weight, V).

/* ---------------------------------------------------------------------------
 *  FIN DEL CICLO
 * ------------------------------------------------------------------------- */
+!end_exit_cycle(TriggerGroup) <-
    -trigger_group(_);
    !unblock_group(TriggerGroup);
    .send(supervisor, tell, exit_cycle_ended(TriggerGroup));
    .print("Scheduler: FIN ciclo de salida (trigger=", TriggerGroup, ")");
    !flush_all_pending_announce;
    !chain_or_release.

+!chain_or_release : pending_queue([Next | Rest]) <-
    -+pending_queue(Rest);
    .print("Scheduler: cola pendiente — encadenando deadline ", Next,
           " (resto en cola = ", Rest, ")");
    !run_one_deadline(Next).

+!chain_or_release <-
    -exit_cycle_active;
    .print("Scheduler: cola de deadlines vacía — exit_cycle_active liberado").

+!flush_all_pending_announce <-
    .findall(p(C, W, H, Wt, Tags), pending_announce(C, W, H, Wt, Tags), All);
    !replay_pending_list(All).

+!replay_pending_list([]).
+!replay_pending_list([p(C, W, H, Wt, Tags) | Rest]) <-
    -pending_announce(C, W, H, Wt, Tags);
    !announce_if_allowed(C, W, H, Wt, Tags);
    !replay_pending_list(Rest).
