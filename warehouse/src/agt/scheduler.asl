/*******************************************************************************
 * SCHEDULER - Agente planificador
 *
 * Única responsabilidad activa por ahora:
 *   Garantizar que todo paquete en zona de entrada/clasificación sea
 *   ACCESIBLE para los robots. Si un paquete no es accesible (está atrapado
 *   por otros paquetes), lo reubica a una celda libre y accesible de la
 *   zona de clasificación mediante la acción relocate_container.
 *
 * Enfoque: entorno ligero — el entorno expone percepts pasivos:
 *   - occupied(X, Y)                    (celdas con paquete)
 *   - container_at(CId, X, Y)          (posición actual de un contenedor)
 *   - new_container(CId)               (disparador)
 * y la acción relocate_container(CId, DestX, DestY) es "tonta": solo mueve
 * el paquete si destino es una celda CLASSIFICATION libre. La decisión la
 * toma este agente mediante un BFS sobre la pequeña topología fija de la
 * zona de entrada/clasificación.
 ******************************************************************************/

/* ============================================================================
 * TOPOLOGÍA (hardcoded — coincide con WarehouseModel.initializeGrid)
 *   Zona de clasificación: x in [3..4], y in [0..1]
 *   Zona de entrada:       x in [5..7], y in [0..1]
 *   Zona EMPTY alcanzable desde zonas:
 *     (x, 2) para x in [3..7]           (no hay shelf hasta x=10)
 *     (8, 0), (8, 1)                     (lateral derecho)
 * ============================================================================ */

zone_cell(3,0). zone_cell(3,1). zone_cell(4,0). zone_cell(4,1).
zone_cell(5,0). zone_cell(5,1). zone_cell(6,0). zone_cell(6,1).
zone_cell(7,0). zone_cell(7,1).

classification_cell(3,0). classification_cell(3,1).
classification_cell(4,0). classification_cell(4,1).

// Celdas EMPTY directamente adyacentes a la zona (salidas hacia el almacén)
empty_exit(3,2). empty_exit(4,2). empty_exit(5,2). empty_exit(6,2). empty_exit(7,2).
empty_exit(8,0). empty_exit(8,1).

/* ============================================================================
 * TOPOLOGÍA DE ESTANTERÍAS (replicado de WarehouseModel.initializeShelves)
 *   shelf_location(Id, X, Y)   — esquina origen, para distancias Manhattan
 *   urgent_shelf(Id)           — solo estas admiten paquetes urgentes
 * El supervisor es el dueño de la CAPACIDAD: el scheduler le pregunta por
 * cada estantería en orden de preferencia hasta recibir "yes".
 * ============================================================================ */
shelf_location(shelf_1, 10,  2).
shelf_location(shelf_2, 12,  2).
shelf_location(shelf_3, 14,  2).
shelf_location(shelf_4, 16,  2).
shelf_location(shelf_5, 10,  6).
shelf_location(shelf_6, 13,  6).
shelf_location(shelf_7, 16,  6).
shelf_location(shelf_8, 10, 10).
shelf_location(shelf_9, 14, 10).

urgent_shelf(shelf_1).
urgent_shelf(shelf_5).
urgent_shelf(shelf_8).

!start.

+!start <-
    .print("Scheduler online. Vigilando accesibilidad de paquetes...").

/* ============================================================================
 * DISPARADORES
 * ============================================================================ */

// Cada vez que entra un contenedor, revisa accesibilidad de TODOS los
// paquetes en zona (un nuevo paquete puede atrapar a otros existentes) y
// consulta la información del paquete para el log.
+new_container(CId) <-
    .print("Scheduler: nuevo contenedor ", CId, ". Revisando accesibilidad...");
    !check_all_packages;
    get_container_info(CId).

// Cuando llega la info del contenedor, la cacheamos, la enviamos al
// supervisor (registro del paquete entrante) y la distribuimos a los
// robots (así se evita que cada robot la pida al entorno y reciba
// percepciones duplicadas que provocan encolados repetidos).
+container_info(CId, W, H, Weight, Type) <-
    V = W * H;
    .abolish(package_info(CId, _, _));
    +package_info(CId, Weight, V);
    .send(supervisor, tell, package_arrived(CId, Weight, V, Type));
    .send(robot_light,  tell, container_info(CId, W, H, Weight, Type));
    .send(robot_medium, tell, container_info(CId, W, H, Weight, Type));
    .send(robot_heavy,  tell, container_info(CId, W, H, Weight, Type));
    .print("Scheduler: log ", CId, " peso=", Weight, " vol=", V, " tipo=", Type);
    -container_info(CId, W, H, Weight, Type).

// Robot notifica al scheduler que depositó el contenedor en un shelf.
// El scheduler reenvía al supervisor con peso y volumen para que éste
// actualice la ocupación de la estantería y verifique los límites.
+guardado(CId, Shelf)[source(R)] : package_info(CId, Weight, V) <-
    .print("Scheduler: ", R, " depositó ", CId, " en ", Shelf);
    .send(supervisor, tell, package_stored(CId, Shelf, Weight, V));
    .abolish(package_info(CId, _, _));
    -guardado(CId, Shelf)[source(R)].

+guardado(CId, Shelf)[source(R)] <-
    .print("Scheduler: ", R, " depositó ", CId, " en ", Shelf, " (sin info en log)");
    .send(supervisor, tell, package_stored(CId, Shelf, 0, 0));
    -guardado(CId, Shelf)[source(R)].

+!check_all_packages <-
    .findall(ca(Id, X, Y), container_at(Id, X, Y), L);
    !process_each(L).

+!process_each([]).
+!process_each([ca(Id, X, Y) | Rest]) <-
    !ensure_accessible(Id, X, Y);
    !process_each(Rest).

/* ============================================================================
 * COMPROBAR ACCESIBILIDAD Y REUBICAR SI ES NECESARIO
 * ============================================================================ */

+!ensure_accessible(CId, X, Y) <-
    !is_accessible(X, Y, R);
    if (R \== true) {
        .print("Scheduler: ", CId, " en (", X, ",", Y, ") NO accesible. Reubicando...");
        !relocate_safely(CId)
    }.

// Busca una celda de CLASSIFICATION libre Y accesible y reubica allí.
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

/* ============================================================================
 * BFS DE ACCESIBILIDAD
 *   Desde (X, Y) se puede llegar a una celda empty_exit SIN pisar celdas
 *   occupied/2 (otros paquetes). La celda origen NO cuenta como muro (es
 *   donde está el propio paquete).
 * ============================================================================ */

+!is_accessible(X, Y, R) <-
    !bfs([pos(X, Y)], [pos(X, Y)], R).

// Cola vacía: no hay salida
+!bfs([], _, false).

// Cabeza es una celda de salida
+!bfs([pos(X, Y) | _], _, true) : empty_exit(X, Y).

// Expande vecinos transitables no visitados
+!bfs([pos(X, Y) | Rest], Visited, R) <-
    XP = X + 1; XM = X - 1; YP = Y + 1; YM = Y - 1;
    Ns = [pos(XP, Y), pos(XM, Y), pos(X, YP), pos(X, YM)];
    !filter_passable(Ns, Visited, NewOnes);
    .concat(Rest, NewOnes, NextQueue);
    .concat(Visited, NewOnes, NewVisited);
    !bfs(NextQueue, NewVisited, R).

/* Filtra los vecinos que:
 *   - no están ya en Visited
 *   - son empty_exit  O bien  son zone_cell no ocupada
 */
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

// Cualquier otra (shelf/exit/fuera de grid/ocupada) se descarta
+!filter_passable([_ | Rest], Visited, Out) <-
    !filter_passable(Rest, Visited, Out).

/* ============================================================================
 * ASIGNACIÓN DE ESTANTERÍA (scheduler = decisor, supervisor = capacidad)
 *
 * Protocolo:
 *   Robot      → Scheduler : request_shelf(CId, W, V, Type, RX, RY)
 *   Scheduler  construye lista ordenada por heurística
 *   Scheduler ←→ Supervisor: can_store / can_store_reply (por cada candidata)
 *   Scheduler  → Robot     : shelf_assigned(CId, ShelfOrNone)
 *
 * Heurística:
 *   urgente     → solo urgentes {1,5,8}, la más cercana al robot que acepte.
 *   no urgente  → tier por peso (pequeña primero si el paquete es ligero),
 *                 cae a tiers mayores si las preferidas están excluidas/llenas.
 *
 * Exclusión dinámica:
 *   - shelf_near_full llegado del supervisor (≥90% o rebasada)
 *   - drop_failed reportado por un robot
 * ============================================================================ */

+request_shelf(CId, W, V, Type, RX, RY)[source(R)] <-
    .print("Scheduler: ", R, " pide estantería para ", CId,
           " (", Type, ", w=", W, ", v=", V, ")");
    !pick_shelf_for(CId, W, V, Type, RX, RY, R);
    -request_shelf(CId, W, V, Type, RX, RY)[source(R)].

+!pick_shelf_for(CId, W, V, Type, RX, RY, Robot) <-
    !build_candidates(Type, W, RX, RY, Cands);
    .print("Scheduler: candidatos ", CId, " = ", Cands);
    !iterate_and_ask(CId, Cands, W, V, Chosen);
    .send(Robot, tell, shelf_assigned(CId, Chosen));
    .print("Scheduler: ", CId, " → ", Chosen, " (", Robot, ")").

/* ---- Construcción de la lista de candidatas ---- */

+!build_candidates(urgent, _, RX, RY, Sorted) <-
    !filter_excluded([shelf_1, shelf_5, shelf_8], Filtered);
    !sort_by_distance(Filtered, RX, RY, Sorted).

+!build_candidates(_, W, _, _, Filtered) <-
    !tier_list(W, Raw);
    !filter_excluded(Raw, Filtered).

/* Preferencia por tier de peso (solo estanterías NO urgentes).
 * Se PRIORIZA el tier propio pero se incluyen el resto como fallback:
 * si las preferidas no aceptan (capacidad/peso/exclusión), se intenta en
 * las siguientes. El supervisor filtra por capacidad real. */
+!tier_list(W, [shelf_2, shelf_3, shelf_4, shelf_6, shelf_7, shelf_9]) : W <= 10.
+!tier_list(W, [shelf_6, shelf_7, shelf_9, shelf_2, shelf_3, shelf_4]) : W <= 30.
+!tier_list(_, [shelf_9, shelf_6, shelf_7, shelf_2, shelf_3, shelf_4]).

+!filter_excluded([], []).
+!filter_excluded([H | T], Out) : shelf_excluded(H) <-
    !filter_excluded(T, Out).
+!filter_excluded([H | T], [H | Out]) <-
    !filter_excluded(T, Out).

/* Ordenar por distancia Manhattan a (RX, RY) — selección del más cercano
 * en cada pasada y eliminación de la lista. */
+!sort_by_distance([], _, _, []).
+!sort_by_distance(L, RX, RY, [Best | Rest]) <-
    !find_closest(L, RX, RY, 999999, none, Best);
    .delete(Best, L, Without);
    !sort_by_distance(Without, RX, RY, Rest).

+!find_closest([], _, _, _, Best, Best).
+!find_closest([H | T], RX, RY, MinD, Cur, Best) :
        shelf_location(H, SX, SY) <-
    D = math.abs(SX - RX) + math.abs(SY - RY);
    if (D < MinD) {
        !find_closest(T, RX, RY, D, H, Best)
    } else {
        !find_closest(T, RX, RY, MinD, Cur, Best)
    }.

/* ---- Preguntar al supervisor por cada candidata en orden ---- */

+!iterate_and_ask(_, [], _, _, none).
+!iterate_and_ask(CId, [H | T], W, V, Chosen) <-
    !ask_supervisor(CId, H, W, V, Ans);
    if (Ans == yes) {
        Chosen = H
    } else {
        !iterate_and_ask(CId, T, W, V, Chosen)
    }.

+!ask_supervisor(CId, Shelf, W, V, Ans) <-
    .abolish(can_store_reply(CId, Shelf, _));
    .send(supervisor, tell, can_store(CId, Shelf, W, V));
    .wait({+can_store_reply(CId, Shelf, _)}, 3000, _);
    if (can_store_reply(CId, Shelf, A)) {
        Ans = A;
        .abolish(can_store_reply(CId, Shelf, _));
    } else {
        .print("Scheduler: timeout preguntando por ", Shelf, ", asumo no");
        Ans = no
    }.

/* ---- Exclusión desde el supervisor (umbral 90% o rebasada) ---- */

+shelf_near_full(Shelf)[source(supervisor)] : not shelf_excluded(Shelf) <-
    +shelf_excluded(Shelf);
    .print("Scheduler: ", Shelf, " excluida por aviso del supervisor");
    -shelf_near_full(Shelf)[source(supervisor)].

+shelf_near_full(Shelf)[source(supervisor)] <-
    -shelf_near_full(Shelf)[source(supervisor)].

/* ---- Fallo al depositar reportado por un robot ---- */

+drop_failed(CId, Shelf)[source(R)] <-
    .print("Scheduler: ", R, " falló drop ", CId, " en ", Shelf, ", excluyo");
    +shelf_excluded(Shelf);
    -drop_failed(CId, Shelf)[source(R)].
