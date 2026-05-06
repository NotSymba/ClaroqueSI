/*******************************************************************************
 * SUPERVISOR - Agente de Monitorización y Gestión de Errores
 *
 * RESPONSABILIDADES:
 *   1. Monitorizar estado global del sistema y métricas.
 *   2. Mantener ocupación real de cada estantería (shelf_usage).
 *   3. Saber qué paquete está en qué estantería con sus etiquetas
 *      (stored_at(CId, Shelf, Tags, Weight, Volume)).
 *   4. Detectar falta de espacio POR GRUPO (urgent | normal) y avisar al
 *      scheduler con no_space(Group). Al liberarse espacio queda
 *      implícito (el scheduler sigue su flujo).
 *   5. Proveer al scheduler la lista de paquetes almacenados de un grupo
 *      cuando abre un deadline de salida (list_stored(Group, Kind) →
 *      stored_list_response(Kind, [...])).
 *
 * MODELO DE ETIQUETAS:
 *   Cada paquete trae un atributo Tags (lista) que puede contener
 *   `urgent`, `fragile`, `standard`. La pertenencia al grupo de salida la
 *   determina la presencia de `urgent`:
 *     tags_group(Tags, urgent) :- .member(urgent, Tags).
 *     tags_group(Tags, normal) :- not .member(urgent, Tags).
 ******************************************************************************/

/* ============================================================================
 * MÉTRICAS
 * ============================================================================ */
total_errors(0).
errors_by_type(container_too_heavy, 0).
errors_by_type(container_too_big, 0).
errors_by_type(shelf_full, 0).
errors_by_type(illegal_move, 0).
errors_by_type(conflict, 0).
errors_by_type(route_blocked, 0).

system_start_time(0).
max_errors_per_minute(10).
max_consecutive_errors(999).

total_received(0).
total_stored(0).

deadline_violations(0).

/* ============================================================================
 * TOPOLOGÍA DE ESTANTERÍAS
 *   urgent_shelf(S)  → shelves S1, S5, S8 (admiten Tags con `urgent`)
 *   regular_shelf(S) → resto (admiten Tags sin `urgent`, i.e. standard/fragile)
 *
 *   La regla shelf_admits(Tags, S) sustituye al antiguo shelf_accepts/2
 *   indexado por átomo de tipo: ahora es por presencia/ausencia de `urgent`.
 * ============================================================================ */
shelf_capacity(shelf_1, 50,  8).
shelf_capacity(shelf_2, 50,  8).
shelf_capacity(shelf_3, 50,  8).
shelf_capacity(shelf_4, 50,  8).
shelf_capacity(shelf_5, 100, 12).
shelf_capacity(shelf_6, 100, 12).
shelf_capacity(shelf_7, 100, 12).
shelf_capacity(shelf_8, 200, 20).
shelf_capacity(shelf_9, 200, 20).

shelf_usage(shelf_1, 0, 0).
shelf_usage(shelf_2, 0, 0).
shelf_usage(shelf_3, 0, 0).
shelf_usage(shelf_4, 0, 0).
shelf_usage(shelf_5, 0, 0).
shelf_usage(shelf_6, 0, 0).
shelf_usage(shelf_7, 0, 0).
shelf_usage(shelf_8, 0, 0).
shelf_usage(shelf_9, 0, 0).

urgent_shelf(shelf_1).  urgent_shelf(shelf_5).  urgent_shelf(shelf_8).
regular_shelf(shelf_2). regular_shelf(shelf_3). regular_shelf(shelf_4).
regular_shelf(shelf_6). regular_shelf(shelf_7). regular_shelf(shelf_9).

shelf_admits(Tags, S) :- .member(urgent, Tags) & urgent_shelf(S).
shelf_admits(Tags, S) :- not .member(urgent, Tags) & regular_shelf(S).

/* Umbral "casi lleno" (marca una shelf individual como ocupada) */
near_full_ratio(0.9).

/* Umbral de saturación POR GRUPO. Si la ocupación agregada (peso o volumen)
 * de las shelves del grupo supera el 70 %, avisamos al scheduler con
 * no_space(Group). */
type_full_ratio(0.7).

/* Mapping de etiquetas a grupo de salida. Sólo importa la presencia de
 * `urgent`; las demás caen al grupo normal. */
tags_group(Tags, urgent) :- .member(urgent, Tags).
tags_group(Tags, normal) :- not .member(urgent, Tags).

/* shelves_of_group/2: shelves que pertenecen a cada grupo. */
shelf_in_group(urgent, S) :- urgent_shelf(S).
shelf_in_group(normal, S) :- regular_shelf(S).

/* Periodicidad del snapshot autoritativo. */
snapshot_period_ms(15000).

!start.

+!start : true <-
    .print("Supervisor iniciado y monitorizando el almacén...");
    !!periodic_snapshot.

+!periodic_snapshot : snapshot_period_ms(P) <-
    .wait(P);
    !broadcast_usage_snapshot;
    !!periodic_snapshot.

+new_container(CId) : total_received(N) <-
    -+total_received(N+1);
    .print("Nuevo contenedor detectado por supervisor. Total recibidos: ", N+1).

/* ============================================================================
 * LOG DE ENTRADA
 * ============================================================================ */

+package_arrived(CId, Weight, Volume, Tags)[source(scheduler)] <-
    +at_warehouse(CId, Tags, Weight, Volume);
    .print("Supervisor: registrado ", CId, " peso=", Weight, " vol=", Volume, " tags=", Tags);
    -package_arrived(CId, Weight, Volume, Tags)[source(scheduler)].

/* ============================================================================
 * ALMACENAMIENTO — actualiza ocupación y verifica límites/grupo.
 * ============================================================================ */

@pkg_stored_known[atomic]
+package_stored(CId, Shelf, Weight, Volume, Tags)[source(scheduler)] :
        shelf_capacity(Shelf, MaxW, MaxV) & total_stored(N) <-
    +stored_at(CId, Shelf, Tags, Weight, Volume);
    !recompute_shelf_usage(Shelf);
    ?shelf_usage(Shelf, NewW, NewV);
    -+total_stored(N + 1);
    .print("Supervisor: ", CId, " → ", Shelf,
           " | peso ", NewW, "/", MaxW, "kg  vol ", NewV, "/", MaxV, "u³");
    -package_stored(CId, Shelf, Weight, Volume, Tags)[source(scheduler)];
    !check_shelf_limits(Shelf, NewW, NewV, MaxW, MaxV);
    !check_group_space(Tags);
    !broadcast_usage_snapshot;
    !calculate_statistics.

@pkg_stored_unknown[atomic]
+package_stored(CId, Shelf, W, V, Tags)[source(scheduler)] : total_stored(N) <-
    -+total_stored(N + 1);
    .print("Supervisor: AVISO shelf desconocido ", Shelf, " para ", CId);
    -package_stored(CId, Shelf, W, V, Tags)[source(scheduler)].

/* ----------------------------------------------------------------------------
 *  Umbrales de estantería individual.
 * -------------------------------------------------------------------------- */
+!check_shelf_limits(Shelf, CurW, _, MaxW, _) : CurW > MaxW <-
    .print("¡ALERTA! ", Shelf, " REBASÓ peso: ", CurW, "/", MaxW, "kg");
    !mark_full(Shelf).
+!check_shelf_limits(Shelf, _, CurV, _, MaxV) : CurV > MaxV <-
    .print("¡ALERTA! ", Shelf, " REBASÓ volumen: ", CurV, "/", MaxV, "u³");
    !mark_full(Shelf).
+!check_shelf_limits(Shelf, CurW, _, MaxW, _) :
        near_full_ratio(R) & CurW >= MaxW * R <-
    .print("Supervisor: ", Shelf, " casi al tope (peso ", CurW, "/", MaxW, "kg)");
    !mark_full(Shelf).
+!check_shelf_limits(Shelf, _, CurV, _, MaxV) :
        near_full_ratio(R) & CurV >= MaxV * R <-
    .print("Supervisor: ", Shelf, " casi al tope (vol ", CurV, "/", MaxV, "u³)");
    !mark_full(Shelf).
+!check_shelf_limits(_, _, _, _, _).

+!mark_full(Shelf) : not shelf_full_marked(Shelf) <-
    +shelf_full_marked(Shelf);
    .send(scheduler, tell, shelf_full(Shelf));
    .print("Supervisor: ", Shelf, " marcada como sin espacio útil").
+!mark_full(_).

/* ============================================================================
 * DETECCIÓN DE FALTA DE ESPACIO POR GRUPO (70% agregado)
 *   Se suma peso/volumen usado y capacidad total de TODAS las shelves del
 *   grupo (urgent_shelf | regular_shelf); si alguna ratio ≥ 0.7, avisamos al
 *   scheduler con no_space(Group). Una sola vez por grupo mientras siga
 *   saturado (blocked_group_notified).
 * ============================================================================ */

+!check_group_space(Tags) :
        tags_group(Tags, Group) & blocked_group_notified(Group) <- true.

+!check_group_space(Tags) :
        tags_group(Tags, Group) & type_full_ratio(R) <-
    !sum_group_usage(Group, UW, UV, MW, MV);
    if (MW > 0 & (UW >= MW * R | UV >= MV * R)) {
        +blocked_group_notified(Group);
        .print("Supervisor: grupo ", Group, " al ", UW, "/", MW, "kg (", UV, "/", MV, "u³) ≥ ",
               R*100, "% — avisando scheduler con no_space(", Group, ")");
        log_event(no_space_detected, Group);
        .send(scheduler, tell, no_space(Group))
    }.

/* Suma sobre las shelves del grupo. */
+!sum_group_usage(Group, UW, UV, MW, MV) <-
    .findall(S, shelf_in_group(Group, S), Shelves);
    .findall(used(W, V),
             (.member(S, Shelves) & shelf_usage(S, W, V)),
             UL);
    .findall(cap(MaxW, MaxV),
             (.member(S, Shelves) & shelf_capacity(S, MaxW, MaxV)),
             CL);
    !sum_uv(UL, 0, 0, UW, UV);
    !sum_mv(CL, 0, 0, MW, MV).

+!sum_uv([], AW, AV, AW, AV).
+!sum_uv([used(W, V) | Rest], AW, AV, UW, UV) <-
    !sum_uv(Rest, AW + W, AV + V, UW, UV).

+!sum_mv([], AW, AV, AW, AV).
+!sum_mv([cap(W, V) | Rest], AW, AV, UW, UV) <-
    !sum_mv(Rest, AW + W, AV + V, UW, UV).

/* ============================================================================
 * LIBERACIÓN DE ESPACIO
 * ============================================================================ */

+package_retrieved(CId, Shelf, Weight, Volume) :
        shelf_capacity(Shelf, MaxW, MaxV) <-
    .abolish(stored_at(CId, _, _, _, _));
    !recompute_shelf_usage(Shelf);
    ?shelf_usage(Shelf, NewW, NewV);
    .print("Supervisor: ", CId, " salió de ", Shelf,
           " | peso ", NewW, "/", MaxW, "kg  vol ", NewV, "/", MaxV, "u³");
    !maybe_unmark(Shelf, NewW, NewV, MaxW, MaxV);
    !broadcast_usage_snapshot;
    -package_retrieved(CId, Shelf, Weight, Volume).

+package_retrieved(CId, Shelf, Weight, Volume) <-
    -package_retrieved(CId, Shelf, Weight, Volume).

+container_exited(CId, Tags, Weight, Volume) <-
    .abolish(at_warehouse(CId, _, _, _));
    .print("Supervisor: ", CId, " (", Tags, ") ha salido del almacén");
    -container_exited(CId, Tags, Weight, Volume).

/* Contenedor aplastado por un robot. */
+container_destroyed(CId, Tags) <-
    .abolish(at_warehouse(CId, _, _, _));
    .print("Supervisor: ", CId, " (", Tags, ") destruido por un robot — purgo registro");
    -container_destroyed(CId, Tags).

+!maybe_unmark(Shelf, CurW, CurV, MaxW, MaxV) :
        near_full_ratio(R) &
        CurW < MaxW * R & CurV < MaxV * R &
        shelf_full_marked(Shelf) <-
    -shelf_full_marked(Shelf);
    .send(scheduler, tell, shelf_free(Shelf));
    .print("Supervisor: ", Shelf, " vuelve a tener espacio").

+!maybe_unmark(_, _, _, _, _).

/* Fin del proceso de salida de un GRUPO. */
+exit_cycle_done(Group)[source(scheduler)] <-
    -blocked_group_notified(Group);
    .print("Supervisor: ciclo de salida del grupo ", Group, " completado");
    -exit_cycle_done(Group)[source(scheduler)].

+exit_cycle_started[source(scheduler)] <-
    .print("Supervisor: scheduler ha iniciado el ciclo de salida");
    -exit_cycle_started[source(scheduler)].

+exit_cycle_ended(Group)[source(scheduler)] <-
    .abolish(blocked_group_notified(_));
    .print("Supervisor: ciclo terminado (trigger=", Group,
           ") — notificaciones reseteadas para todos los grupos");
    !broadcast_usage_snapshot;
    -exit_cycle_ended(Group)[source(scheduler)].

/* ============================================================================
 * RECOMPUTACIÓN DE shelf_usage Y SNAPSHOT AUTORITATIVO A LOS ROBOTS
 * ============================================================================ */

+!recompute_shelf_usage(Shelf) <-
    .findall(uw(W, V), stored_at(_, Shelf, _, W, V), L);
    !sum_uw(L, 0, 0, NewW, NewV);
    .abolish(shelf_usage(Shelf, _, _));
    +shelf_usage(Shelf, NewW, NewV).

+!sum_uw([], AW, AV, AW, AV).
+!sum_uw([uw(W, V) | Rest], AW, AV, OW, OV) <-
    !sum_uw(Rest, AW + W, AV + V, OW, OV).

+!broadcast_usage_snapshot <-
    .findall(usage(S, W, V), shelf_usage(S, W, V), L);
    .send(robot_light,   tell, shelf_usage_snapshot(L));
    .send(robot_medium,  tell, shelf_usage_snapshot(L));
    .send(robot_heavy,   tell, shelf_usage_snapshot(L));
    .send(robot_heavy2,  tell, shelf_usage_snapshot(L)).

/* ============================================================================
 * LIST_STORED — ahora por GRUPO en vez de por lista de tipos.
 *
 *   El scheduler nos pide:
 *       achieve list_stored(Group, Kind)
 *
 *   Respondemos con:
 *       tell stored_list_response(Kind, L)
 *
 *   donde L es lista de s(CId, Shelf, Weight, Volume, Tags) con todos los
 *   stored_at/5 cuyos Tags pertenezcan al grupo solicitado.
 * ============================================================================ */
+!list_stored(Group, Kind)[source(scheduler)] <-
    .findall(s(CId, Shelf, Weight, Volume, Tags),
             (stored_at(CId, Shelf, Tags, Weight, Volume) &
              tags_group(Tags, Group)),
             L);
    .length(L, N);
    .print("Supervisor: list_stored(", Group, ", ", Kind, ") → ", N, " items");
    .send(scheduler, tell, stored_list_response(Kind, L)).

/* ============================================================================
 * ESTADÍSTICAS Y ESTADO DE ROBOTS
 * ============================================================================ */

+!calculate_statistics : total_received(R) & total_stored(S) & R > 0 <-
    SuccessRate = (S / R) * 100;
    .print("--- ESTADÍSTICAS GLOBALES ---");
    .print("Recibidos: ", R, " | Almacenados: ", S, " | Tasa de éxito: ", SuccessRate, "%").

+robot_status(State)[source(Robot)] <-
    .abolish(status_of(Robot, _));
    +status_of(Robot, State);
    .print("Monitor: El robot ", Robot, " ha cambiado su estado a ", State);
    -robot_status(State)[source(Robot)].

@total_errors_update[atomic]
+total_errors(ErrorType, GlobalTotal) <-
    .abolish(total_errors(_));
    +total_errors(GlobalTotal);
    !update_specific_error(ErrorType);
    .abolish(total_errors(_, _)[source(percept)]);
    !check_stop(GlobalTotal).

+!update_specific_error(Type) : errors_by_type(Type, OldCount) <-
    .abolish(errors_by_type(Type, _));
    +errors_by_type(Type, OldCount + 1).

+!update_specific_error(Type) : true <-
    +errors_by_type(Type, 1).

+!check_stop(Total) : max_consecutive_errors(Max) & Total >= Max <-
    .print("¡ALERTA CRÍTICA! Se han alcanzado ", Total, " errores globales (Límite tolerado: ", Max, ").");
    .print("================ REPORTE FINAL DE ERRORES ================");
    for ( errors_by_type(EType, ECount) ) {
        if (ECount > 0) {
            .print(" -> ", EType, " : ", ECount, " veces");
        }
    };
    .print("==========================================================");
    .print("Deteniendo el sistema por seguridad...");
    .wait(10000);
    .stopMAS.

+!check_stop(_) : true <- true.

/* ============================================================================
 * VIGILANCIA TEMPORAL DE DEADLINES
 *
 *   El scheduler avisa con tell deadline_started(Kind, Group, Duration) cuando
 *   arranca un deadline. Tras Duration ms auditamos qué contenedores del grupo
 *   siguen en el almacén (at_warehouse/4).
 * ============================================================================ */

+deadline_started(Kind, Group, Duration)[source(scheduler)] <-
    -deadline_started(Kind, Group, Duration)[source(scheduler)];
    .print("Supervisor: arranco vigilancia temporal de deadline ", Kind,
           " (grupo=", Group, ", duración=", Duration, "ms)");
    !watch_deadline(Kind, Group, Duration).

+!watch_deadline(Kind, Group, Duration) <-
    .wait(Duration);
    !audit_deadline(Kind, Group).

+!audit_deadline(Kind, Group) <-
    .findall(p(CId, Tags),
             (at_warehouse(CId, Tags, _, _) & tags_group(Tags, Group)),
             Pending);
    .length(Pending, N);
    !report_audit(Kind, Group, N, Pending).

+!report_audit(Kind, _, 0, _) <-
    .print("Supervisor: deadline ", Kind, " cumplido (sin pendientes)").

+!report_audit(Kind, Group, N, Pending) :
        deadline_violations(K) <-
    .abolish(deadline_violations(_));
    +deadline_violations(K + 1);
    .print("==========================================================");
    .print("ERROR INFORMATIVO | deadline=", Kind, " | grupo=", Group);
    .print("  Contenedores sin entregar al expirar: ", N);
    .print("  Lista: ", Pending);
    .print("  Total incumplimientos acumulados: ", K + 1);
    !emit_deadline_missed_each(Pending);
    .print("==========================================================").

+!emit_deadline_missed_each([]).
+!emit_deadline_missed_each([p(CId, _) | Rest]) <-
    log_event(deadline_missed, CId);
    !emit_deadline_missed_each(Rest).
