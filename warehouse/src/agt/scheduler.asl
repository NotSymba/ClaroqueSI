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
 *      nos envía tell unstorable(CId, Type) y contamos para el ciclo.
 *   4. Recibe el aviso del supervisor cuando no queda espacio para un tipo
 *      (no_space(Type) al 70 %) o acumulamos unstorable_threshold paquetes
 *      sin almacenar: dispara el ciclo de salida del grupo afectado y bloquea
 *      la generación de esos tipos hasta que termina el deadline.
 *
 * Lo que el scheduler NO hace:
 *   - No elige qué estantería usa cada robot (los robots lo deciden en local
 *     usando robot_shelf_priority + shelf_usage_local + shelf_reservation)
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
    .send(robot_heavy,   tell, container_available(CId, W, H, Weight, Type));
    .send(robot_heavy2,  tell, container_available(CId, W, H, Weight, Type)).

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

/* ----------------------------------------------------------------------------
 *  CONTENEDOR APLASTADO POR UN ROBOT (splash). El env destruye el paquete y
 *  notifica a todos los agentes para que purguen referencias. Aquí limpiamos
 *  todo el estado que el scheduler pudiera mantener sobre ese contenedor:
 *  caché de info, anuncios pendientes, claims, exit_items publicados y la
 *  cuenta de unstorable. También retiramos los exit_item / container_available
 *  ya enviados a los robots (untell), por si el contenedor estaba en vuelo
 *  para otro robot.
 * -------------------------------------------------------------------------- */
+container_destroyed(CId, Type) <-
    .print("Scheduler: contenedor ", CId, " (tipo ", Type, ") destruido — limpio referencias");
    .abolish(package_info(CId, _, _, _));
    .abolish(pending_announce(CId, _, _, _, _));
    .abolish(claimed(CId));
    .abolish(pending_exit(CId, _, _, _, _, _));
    .abolish(container_at(CId, _, _));
    !remove_from_unstorable(CId);
    .broadcast(untell, exit_item(CId, _, _, _, _, _));
    .broadcast(untell, container_available(CId, _, _, _, _));
    .broadcast(untell, exit_taken(CId));
    -container_destroyed(CId, Type).

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

delta_t(30000).  // ΔT en milisegundos

unstorable_threshold(3).

/* Cola FIFO de deadlines pendientes mientras hay uno activo. Se rellena
 * cuando llega un trigger (no_space, umbral unstorable, force_exit_cycle)
 * con exit_cycle_active=true. Al cerrar el deadline activo, !end_exit_cycle
 * dispara !chain_or_release que extrae el primer Group encolado y arranca
 * INMEDIATAMENTE otro ciclo SIN liberar exit_cycle_active (así no se cuela
 * un trigger nuevo entre medias). Sólo se libera cuando la cola queda vacía.
 *
 * Dedup: no se encola dos veces el mismo Group ni se encola el grupo del
 * deadline en curso (sería redundante y chocaría con la guarda de supervisor
 * blocked_group_notified). */
pending_queue([]).

/* Registro de unstorable (sigue siendo por GRUPO para que al disparar el ciclo
 * tengamos la lista de pendientes del grupo adecuado). */
+unstorable(CId, Type)[source(_)] <-
    .abolish(unstorable(CId, Type)[source(_)]);
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

/* Disparo forzado desde un robot: caso límite en el que un paquete ya
 * recogido no encuentra shelf que lo acepte (típicamente por desajustes
 * de sincronización o precisión). El robot deposita ese paquete en la
 * zona de salida directamente y nos pide vaciar las estanterías del
 * grupo afectado. */
+force_exit_cycle(Type)[source(_)] :
        type_group(Type, Group) & not exit_cycle_active <-
    .abolish(force_exit_cycle(_)[source(_)]);
    .print("Scheduler: ciclo de salida forzado por robot (grupo ", Group, ") — caso límite");
    !begin_exit_cycle(Group).

+force_exit_cycle(Type)[source(_)] :
        type_group(Type, Group) & exit_cycle_active <-
    .abolish(force_exit_cycle(_)[source(_)]);
    .print("Scheduler: force_exit_cycle(", Type, ") durante ciclo activo — encolando ", Group);
    !enqueue_pending(Group).

+force_exit_cycle(Type)[source(_)] <-
    .abolish(force_exit_cycle(Type)[source(_)]).

/* Disparador desde supervisor: 70 % de un tipo */
+no_space(Type)[source(supervisor)] :
        type_group(Type, Group) & not exit_cycle_active <-
    .print("Scheduler: supervisor avisa no_space(", Type, ") — grupo ", Group);
    -no_space(Type)[source(supervisor)];
    !begin_exit_cycle(Group).

+no_space(Type)[source(supervisor)] :
        type_group(Type, Group) & exit_cycle_active <-
    .print("Scheduler: supervisor avisa no_space(", Type,
           ") durante ciclo activo — encolando grupo ", Group);
    -no_space(Type)[source(supervisor)];
    !enqueue_pending(Group).

+no_space(Type)[source(supervisor)] <-
    -no_space(Type)[source(supervisor)].

/* ---------------------------------------------------------------------------
 *  Arranque del ciclo (T0) — REACTIVO + COLA DE PENDIENTES.
 *
 *  Un disparo activa UN ÚNICO deadline, el del grupo afectado:
 *     - urgent  → deadline CORTO  (ΔT,  solo urgentes, shelves S1/S5/S8)
 *     - normal  → deadline LARGO  (2ΔT, standard+fragile, resto de shelves)
 *
 *  Sólo puede haber UN deadline activo en cada momento (exit_cycle_active es
 *  el lock). Si llega un trigger mientras hay otro deadline en curso, NO se
 *  pierde: se encola en pending_queue (con dedup) y se ejecutará en cuanto
 *  termine el actual. El encadenamiento se hace dentro de !chain_or_release
 *  SIN liberar exit_cycle_active entre uno y otro, para evitar la ventana
 *  de carrera en la que un nuevo trigger podría arrancar otro ciclo en
 *  paralelo.
 *
 *  El supervisor re-emite no_space al recibir exit_cycle_ended (resetea sus
 *  flags blocked_group_notified). Si la saturación persiste tras drenar la
 *  cola, generará un nuevo trigger con exit_cycle_active=false y arrancará
 *  un ciclo limpio.
 * ------------------------------------------------------------------------- */
+!begin_exit_cycle(TriggerGroup) <-
    +exit_cycle_active;
    !run_one_deadline(TriggerGroup).

/* Cuerpo de UN deadline. NO toca exit_cycle_active: el caller (begin_exit_cycle
 * la primera vez, chain_or_release en encadenamientos) gestiona el lock. Esto
 * permite encadenar deadlines pendientes de la cola sin la ventana de carrera
 * que existiría al hacer "-exit_cycle_active; ...; +exit_cycle_active". */
+!run_one_deadline(Group) <-
    +trigger_group(Group);
    !block_group(Group);
    .send(supervisor, tell, exit_cycle_started);
    .print("Scheduler: T0 — INICIO ciclo de salida (grupo=", Group, ")");
    !run_deadline_for(Group);
    !end_exit_cycle(Group).

/* Dispatch: solo el deadline del grupo disparador. */
+!run_deadline_for(urgent) <-
    !run_deadline(short, [urgent], 1).

+!run_deadline_for(normal) <-
    !run_deadline(long, [standard, fragile], 2).

/* Bloqueo per-grupo: sólo para el grupo disparador. */
+!block_group(urgent) <-
    block_generation(urgent);
    +blocked_group(urgent);
    .print("Scheduler: generación URGENT bloqueada (normales siguen fluyendo)").

+!block_group(normal) <-
    block_generation(standard);
    block_generation(fragile);
    +blocked_group(normal);
    .print("Scheduler: generación STANDARD+FRAGILE bloqueada (urgentes siguen fluyendo)").

+!unblock_group(urgent) <-
    unblock_generation(urgent);
    -blocked_group(urgent);
    .print("Scheduler: generación URGENT reanudada").

+!unblock_group(normal) <-
    unblock_generation(standard);
    unblock_generation(fragile);
    -blocked_group(normal);
    .print("Scheduler: generación STANDARD+FRAGILE reanudada").

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
    // Supervisor arranca su propia vigilancia temporal del deadline. Al expirar
    // Duration audita los contenedores de Types que sigan en el almacén y
    // registra un error informativo si quedaron pendientes sin entregar.
    .send(supervisor, tell, deadline_started(Kind, Types, Duration));
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

/* Publica los paquetes del grupo que siguen en entrada/procesamiento:
 *   - unstorable_pending(G, L)  — rechazados por falta de hueco o depositados
 *                                 en clasificación (tell unstorable desde env
 *                                 o desde work.asl cuando no cabe)
 *   - pending_announce(...)    — paquetes del grupo que llegaron durante un
 *                                 bloqueo previo y están sin anunciar. Se
 *                                 cosechan aquí (se convierten en unstorable)
 *                                 para que también salgan por la zona de
 *                                 salida en este deadline, no se acumulen.
 */
+!publish_unstorable_items([], _).
+!publish_unstorable_items([T | Rest], Kind) <-
    ?type_group(T, G);
    !harvest_pending_announce_for_group(G);
    !publish_unstorable_for_group(G, Kind);
    !publish_unstorable_items(Rest, Kind).

// Pasa los pending_announce del grupo a unstorable_pending para que
// entren en el pipeline de salida. No envía tell unstorable al env: los
// paquetes ya están físicamente en entrada (container_at los ubica).
+!harvest_pending_announce_for_group(G) <-
    .findall(pa(CId, W, H, Wt, Ty),
             (pending_announce(CId, W, H, Wt, Ty) & type_group(Ty, G)),
             All);
    !harvest_pa_each(All, G).

+!harvest_pa_each([], _).
+!harvest_pa_each([pa(CId, W, H, Wt, Ty) | Rest], G) <-
    -pending_announce(CId, W, H, Wt, Ty);
    .print("Scheduler: cosecho pending ", CId, " (tipo ", Ty, ") → unstorable del grupo ", G);
    !record_unstorable(CId, G);
    !harvest_pa_each(Rest, G).

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
 *  FIN DEL CICLO — reanuda generación SÓLO del grupo disparador (el otro no
 *  fue bloqueado) + flush de pending_announce.
 *
 *  Enviamos exit_cycle_ended(TriggerGroup) al supervisor con el grupo como
 *  argumento: el supervisor lo usa para resetear SUS notificaciones y volver
 *  a poder emitir no_space si la saturación persiste.
 * ------------------------------------------------------------------------- */
+!end_exit_cycle(TriggerGroup) <-
    // OJO: NO removemos exit_cycle_active aquí. Lo decide chain_or_release:
    //   · si la cola tiene pendientes → encadenamos otro deadline manteniendo
    //     el lock (no hay ventana para que un trigger nuevo arranque otro
    //     ciclo en paralelo);
    //   · si la cola está vacía → liberamos el lock y el sistema queda
    //     disponible para nuevos triggers.
    -trigger_group(_);
    // NO abolimos unstorable_pending: exit_done ya quitó los entregados,
    // así que lo que queda son paquetes que NO salieron en este ciclo y
    // deben volver a publicarse en el siguiente deadline del mismo grupo.
    !unblock_group(TriggerGroup);
    .send(supervisor, tell, exit_cycle_ended(TriggerGroup));
    .print("Scheduler: FIN ciclo de salida (trigger=", TriggerGroup, ")");
    !flush_all_pending_announce;
    !chain_or_release.

/* Si hay otro deadline encolado, lo ejecutamos INMEDIATAMENTE sin liberar
 * exit_cycle_active. Reusa run_one_deadline (que no toca el lock). Si la
 * cola se sigue llenando durante ese deadline, se encadenará igual al cerrar.
 *
 * Si la cola está vacía, sólo entonces liberamos exit_cycle_active. */
+!chain_or_release : pending_queue([Next | Rest]) <-
    -+pending_queue(Rest);
    .print("Scheduler: cola pendiente — encadenando deadline ", Next,
           " (resto en cola = ", Rest, ")");
    !run_one_deadline(Next).

+!chain_or_release <-
    -exit_cycle_active;
    .print("Scheduler: cola de deadlines vacía — exit_cycle_active liberado").

+!flush_all_pending_announce <-
    .findall(p(C, W, H, Wt, Ty), pending_announce(C, W, H, Wt, Ty), All);
    !replay_pending_list(All).

+!replay_pending_list([]).
+!replay_pending_list([p(C, W, H, Wt, Ty) | Rest]) <-
    -pending_announce(C, W, H, Wt, Ty);
    !announce_if_allowed(C, W, H, Wt, Ty);
    !replay_pending_list(Rest).
