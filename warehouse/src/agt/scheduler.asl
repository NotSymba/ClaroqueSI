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
 *  Ocupación (shelf_occupied/1) la avisa el supervisor con shelf_full/shelf_free.
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
 * OCUPACIÓN DE ESTANTERÍAS
 *   El supervisor avisa con shelf_full(Shelf) cuando una shelf deja de tener
 *   espacio útil y shelf_free(Shelf) cuando vuelve a tenerlo. Aquí sólo
 *   mantenemos shelf_occupied/1 como belief local para usar en suggest_shelf.
 * ============================================================================ */
+shelf_full(Shelf)[source(supervisor)] <-
    +shelf_occupied(Shelf);
    .print("Scheduler: ", Shelf, " marcada como ocupada");
    -shelf_full(Shelf)[source(supervisor)].

+shelf_free(Shelf)[source(supervisor)] <-
    -shelf_occupied(Shelf);
    .print("Scheduler: ", Shelf, " vuelve a estar libre");
    -shelf_free(Shelf)[source(supervisor)].

/* ============================================================================
 * SUGERENCIA DE ESTANTERÍA
 *   Un robot pide una shelf donde depositar CId (tipo Type) estando en (RX,RY).
 *   Respuesta: shelf_suggestion(CId, Shelf) — Shelf = none si no hay opciones.
 *   Reglas:
 *     - urgente → la más cercana a (RX,RY) que acepte urgent y no esté ocupada
 *     - otros   → la primera de robot_shelf_priority(Robot, _) que acepte
 *                 el tipo y no esté ocupada
 *     - si ninguna de la lista personal encaja, fallback a cualquiera libre
 *       que acepte el tipo (por si el robot no es conocido o la lista agotó).
 * ============================================================================ */
+!suggest_shelf(CId, Type, RX, RY, Requester) <-
    !pick_suggestion(Requester, Type, RX, RY, Shelf);
    .print("Scheduler: sugiero ", Shelf, " para ", CId, " (tipo ", Type, ", robot ", Requester, ")");
    .send(Requester, tell, shelf_suggestion(CId, Shelf)).

/* Urgentes: siempre la más cercana */
+!pick_suggestion(_, urgent, RX, RY, Shelf) <-
    .findall(s(S, D),
             (shelf_accepts(urgent, S) & not shelf_occupied(S) &
              shelf_location(S, SX, SY) &
              D = math.abs(SX - RX) + math.abs(SY - RY)),
             Cands);
    if (Cands == []) {
        Shelf = none
    } else {
        !min_by_distance(Cands, Shelf)
    }.

/* No urgentes: primero la lista personal, si no encaja nada, cualquier libre */
+!pick_suggestion(Robot, Type, _, _, Shelf) :
        robot_shelf_priority(Robot, Prio) <-
    !first_valid(Prio, Type, Chosen);
    if (Chosen \== none) {
        Shelf = Chosen
    } else {
        .findall(S, (shelf_accepts(Type, S) & not shelf_occupied(S)), Fallback);
        if (Fallback == []) { Shelf = none }
        else { [Shelf | _] = Fallback }
    }.

/* Robot sin lista conocida: cualquier libre que acepte */
+!pick_suggestion(_, Type, _, _, Shelf) <-
    .findall(S, (shelf_accepts(Type, S) & not shelf_occupied(S)), L);
    if (L == []) { Shelf = none } else { [Shelf | _] = L }.

+!first_valid([], _, none).
+!first_valid([S | _], Type, S) :
        shelf_accepts(Type, S) & not shelf_occupied(S).
+!first_valid([_ | Rest], Type, Chosen) <-
    !first_valid(Rest, Type, Chosen).

+!min_by_distance([s(S, D) | Rest], Best) <-
    !min_aux(Rest, S, D, Best).
+!min_aux([], B, _, B).
+!min_aux([s(S, D) | Rest], _, MinD, Best) : D < MinD <-
    !min_aux(Rest, S, D, Best).
+!min_aux([_ | Rest], Cur, MinD, Best) <-
    !min_aux(Rest, Cur, MinD, Best).

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
 *  CONTADOR DE UNSTORABLE + DISPARO DE SALIDA
 *
 *  Cuando un robot pregunta por una shelf y no hay ninguna disponible,
 *  marca el paquete como "unstorable" y no lo recoge. El scheduler lo
 *  apunta en unstorable_pending/2. Si acumulamos `unstorable_threshold`
 *  paquetes del mismo tipo, iniciamos el proceso de salida de ese tipo.
 *
 *  Segundo disparador: el supervisor avisa de 70% de ocupación agregada
 *  con no_space(Type).
 *
 *  Durante el ciclo de salida:
 *    1. fase stored_phase: pedimos candidatos al supervisor (paquetes ya
 *       almacenados) y los mandamos a la salida uno a uno.
 *    2. fase unstorable_phase: cuando el supervisor no tiene más, vamos
 *       enviando los unstorable_pending directamente a la salida (el robot
 *       los recoge de la zona de entrada y los deposita en exit).
 *    3. al acabar: desbloqueamos generación + tipo + flush de pendientes.
 * ============================================================================ */

unstorable_threshold(3).

+unstorable(CId, Type)[source(_)] <-
    !record_unstorable(CId, Type);
    -unstorable(CId, Type)[source(_)].

+!record_unstorable(CId, Type) :
        unstorable_pending(Type, L) & .member(CId, L) <-
    true.

+!record_unstorable(CId, Type) :
        unstorable_pending(Type, L) <-
    -+unstorable_pending(Type, [CId | L]);
    .length([CId | L], N);
    .print("Scheduler: unstorable ", CId, " (", Type, "). Pendientes=", N);
    !check_unstorable_threshold(Type, N).

+!record_unstorable(CId, Type) <-
    +unstorable_pending(Type, [CId]);
    .print("Scheduler: unstorable ", CId, " (", Type, "). Pendientes=1");
    !check_unstorable_threshold(Type, 1).

+!check_unstorable_threshold(Type, N) :
        unstorable_threshold(T) & N >= T & not blocked_type(Type) <-
    .print("Scheduler: umbral unstorable alcanzado para ", Type);
    !trigger_exit_cycle(Type).
+!check_unstorable_threshold(_, _).

+no_space(Type)[source(supervisor)] : not blocked_type(Type) <-
    .print("Scheduler: supervisor avisa no_space(", Type, ")");
    !trigger_exit_cycle(Type);
    -no_space(Type)[source(supervisor)].

+no_space(Type)[source(supervisor)] <-
    -no_space(Type)[source(supervisor)].

+!trigger_exit_cycle(Type) <-
    +blocked_type(Type);
    +exit_phase(Type, stored_phase);
    block_generation(Type);
    .print("Scheduler: INICIO ciclo salida ", Type, " — bloqueo entrada");
    .send(supervisor, achieve, request_exit_candidate(Type)).

/* -------- FASE 1: desalojo de paquetes almacenados -------- */

+exit_candidate(CId, Shelf, Weight, V, Type)[source(supervisor)] :
        CId \== none <-
    .print("Scheduler: desaloja ", CId, " (", Type, ") de ", Shelf);
    !dispatch_exit(CId, Shelf, Weight, V, Type);
    -exit_candidate(CId, Shelf, Weight, V, Type)[source(supervisor)].

+exit_candidate(none, _, _, _, Type)[source(supervisor)] <-
    .print("Scheduler: supervisor sin más stored de ", Type, " → paso a unstorable");
    -exit_candidate(none, _, _, _, Type)[source(supervisor)];
    -+exit_phase(Type, unstorable_phase);
    !dispatch_next_unstorable(Type).

/* Envío del encargo de salida. Para evitar carreras (dos robots intentando
 * retirar el mismo CId → error invalid_retrieve), mandamos SÓLO al robot
 * más adecuado según peso/volumen. Si ese robot no puede (ocupado, por
 * ejemplo), al próximo container_exited re-disparamos.
 *   Weight <= 10 y V <= 1  → light
 *   Weight <= 30 y V <= 2  → medium
 *   resto                  → heavy (que coordina con heavy2 vía router)
 */
+!dispatch_exit(CId, Shelf, Weight, V, Type) <-
    !pick_exit_robot(Weight, V, Target);
    .print("Scheduler: exit_order ", CId, " (peso=", Weight, ", vol=", V, ") → ", Target);
    .send(Target, tell, exit_order(CId, Shelf, Weight, V, Type)).

+!pick_exit_robot(Weight, V, robot_light) :
        Weight <= 10 & V <= 1.
+!pick_exit_robot(Weight, V, robot_medium) :
        Weight <= 30 & V <= 2.
+!pick_exit_robot(_, _, robot_heavy).

/* Un robot nos avisa si no puede con un exit_order; escalamos al siguiente
 * robot más capaz. Shelf=none significa que venía de exit_direct_order. */
+exit_reject(CId, Shelf, Weight, V, Type)[source(Robot)] <-
    .print("Scheduler: ", Robot, " rechaza ", CId, " (peso=", Weight, ") — escalando");
    -exit_reject(CId, Shelf, Weight, V, Type)[source(Robot)];
    !escalate_exit(CId, Shelf, Weight, V, Type, Robot).

+!escalate_exit(CId, Shelf, Weight, V, Type, robot_light) :
        Shelf \== none <-
    .send(robot_medium, tell, exit_order(CId, Shelf, Weight, V, Type)).
+!escalate_exit(CId, _, Weight, V, Type, robot_light) <-
    .send(robot_medium, tell, exit_direct_order(CId, Weight, V, Type)).

+!escalate_exit(CId, Shelf, Weight, V, Type, robot_medium) :
        Shelf \== none <-
    .send(robot_heavy, tell, exit_order(CId, Shelf, Weight, V, Type)).
+!escalate_exit(CId, _, Weight, V, Type, robot_medium) <-
    .send(robot_heavy, tell, exit_direct_order(CId, Weight, V, Type)).

+!escalate_exit(CId, _, _, _, _, _) <-
    .print("Scheduler: sin escalada posible para ", CId, " — ciclo puede bloquearse").

/* -------- FASE 2: unstorable que se llevan desde la zona de entrada -------- */

+!dispatch_next_unstorable(Type) :
        unstorable_pending(Type, []) <-
    !finish_exit_cycle(Type).

+!dispatch_next_unstorable(Type) :
        unstorable_pending(Type, [CId | Rest]) <-
    -+unstorable_pending(Type, Rest);
    .print("Scheduler: mando ", CId, " (unstorable ", Type, ") directo a salida");
    !dispatch_exit_direct(CId, Type).

+!dispatch_next_unstorable(Type) <-
    !finish_exit_cycle(Type).

+!dispatch_exit_direct(CId, Type) :
        package_info(CId, Weight, V, _) <-
    !pick_exit_robot(Weight, V, Target);
    .print("Scheduler: exit_direct_order ", CId, " → ", Target);
    .send(Target, tell, exit_direct_order(CId, Weight, V, Type)).

+!dispatch_exit_direct(CId, Type) <-
    // Sin info cacheada: asumimos peor caso → heavy
    .print("Scheduler: exit_direct_order ", CId, " (sin info) → robot_heavy");
    .send(robot_heavy, tell, exit_direct_order(CId, 0, 0, Type)).

/* Cada vez que un paquete sale efectivamente del almacén avanzamos el ciclo.
 * El entorno emite container_exited(CId, Type, W, V) al drop_at_exit. */
+container_exited(CId, Type, Weight, V) :
        blocked_type(Type) & exit_phase(Type, stored_phase) <-
    .print("Scheduler: ", CId, " (", Type, ") salió — pido siguiente stored");
    .abolish(package_info(CId, _, _, _));
    .send(supervisor, achieve, request_exit_candidate(Type));
    -container_exited(CId, Type, Weight, V).

+container_exited(CId, Type, Weight, V) :
        blocked_type(Type) & exit_phase(Type, unstorable_phase) <-
    .print("Scheduler: ", CId, " (", Type, ") salió — siguiente unstorable");
    .abolish(package_info(CId, _, _, _));
    -container_exited(CId, Type, Weight, V);
    !dispatch_next_unstorable(Type).

/* Fallback: container_exited fuera de ciclo (no debería pasar, pero por
 * seguridad limpiamos la caché). */
+container_exited(CId, Type, Weight, V) <-
    .print("Scheduler: ", CId, " (", Type, ") salió del almacén (fuera de ciclo)");
    .abolish(package_info(CId, _, _, _));
    -container_exited(CId, Type, Weight, V).

/* -------- FIN DEL CICLO: desbloquea tipo y generación -------- */

+!finish_exit_cycle(Type) <-
    -blocked_type(Type);
    -exit_phase(Type, _);
    unblock_generation(Type);
    .send(supervisor, tell, exit_cycle_done(Type));
    .print("Scheduler: FIN ciclo salida ", Type, " — reanudo generación");
    !flush_pending(Type).

+!flush_pending(Type) <-
    .findall(p(C, W, H, Wt), pending_announce(C, W, H, Wt, Type), Pend);
    !replay_pending(Type, Pend).

+!replay_pending(_, []).
+!replay_pending(Type, [p(C, W, H, Wt) | Rest]) <-
    -pending_announce(C, W, H, Wt, Type);
    !announce_if_allowed(C, W, H, Wt, Type);
    !replay_pending(Type, Rest).
