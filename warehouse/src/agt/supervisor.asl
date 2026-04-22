/*******************************************************************************
 * SUPERVISOR - Agente de Monitorización y Gestión de Errores
 *
 * RESPONSABILIDADES:
 *   1. Monitorizar estado global del sistema y métricas.
 *   2. Mantener ocupación real de cada estantería (shelf_usage).
 *   3. Saber qué paquete está en qué estantería y de qué tipo
 *      (stored_at(CId, Shelf, Type, Weight, Volume)).
 *   4. Detectar falta de espacio POR TIPO de contenedor y avisar al scheduler
 *      con no_space(Type). Al liberarse espacio, avisar con space_available(Type).
 *   5. Proveer al scheduler un candidato de desalojo cuando éste lanza el ciclo
 *      de salida (request_exit_candidate(Type) → exit_candidate(...)).
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
max_consecutive_errors(100).

total_received(0).
total_stored(0).

/* ============================================================================
 * TOPOLOGÍA DE ESTANTERÍAS
 *   shelf_capacity(Id, MaxWeight, MaxVolume)
 *   shelf_usage(Id, CurWeight, CurVolume)      — sincronizada con el entorno
 *   shelf_accepts(Type, Shelf)                  — qué tipos admite cada una
 *       urgentes: S1, S5, S8
 *       estándar + frágil: S2, S3, S4, S6, S7, S9
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

shelf_accepts(urgent,   shelf_1).
shelf_accepts(urgent,   shelf_5).
shelf_accepts(urgent,   shelf_8).
shelf_accepts(standard, shelf_2).
shelf_accepts(standard, shelf_3).
shelf_accepts(standard, shelf_4).
shelf_accepts(standard, shelf_6).
shelf_accepts(standard, shelf_7).
shelf_accepts(standard, shelf_9).
shelf_accepts(fragile,  shelf_2).
shelf_accepts(fragile,  shelf_3).
shelf_accepts(fragile,  shelf_4).
shelf_accepts(fragile,  shelf_6).
shelf_accepts(fragile,  shelf_7).
shelf_accepts(fragile,  shelf_9).

/* Umbral "casi lleno" (marca una shelf individual como ocupada) */
near_full_ratio(0.9).

/* Umbral de saturación POR TIPO. Si la ocupación agregada (peso o volumen)
 * de las estanterías que admiten un tipo supera el 70%, se avisa al scheduler
 * con no_space(Type) para que dispare el proceso de salida. */
type_full_ratio(0.7).

!start.

+!start : true <-
    .print("Supervisor iniciado y monitorizando el almacén...").

+new_container(CId) : total_received(N) <-
    -+total_received(N+1);
    .print("Nuevo contenedor detectado por supervisor. Total recibidos: ", N+1).

/* ============================================================================
 * LOG DE ENTRADA
 * ============================================================================ */

+package_arrived(CId, Weight, Volume, Type)[source(scheduler)] <-
    .print("Supervisor: registrado ", CId, " peso=", Weight, " vol=", Volume, " tipo=", Type);
    -package_arrived(CId, Weight, Volume, Type)[source(scheduler)].

/* ============================================================================
 * ALMACENAMIENTO — actualiza ocupación y verifica límites/tipo.
 * ============================================================================ */

@pkg_stored_known[atomic]
+package_stored(CId, Shelf, Weight, Volume, Type)[source(scheduler)] :
        shelf_capacity(Shelf, MaxW, MaxV) & shelf_usage(Shelf, UW, UV) &
        total_stored(N) <-
    NewW = UW + Weight;
    NewV = UV + Volume;
    .abolish(shelf_usage(Shelf, _, _));
    +shelf_usage(Shelf, NewW, NewV);
    +stored_at(CId, Shelf, Type, Weight, Volume);
    -+total_stored(N + 1);
    .print("Supervisor: ", CId, " → ", Shelf,
           " | peso ", NewW, "/", MaxW, "kg  vol ", NewV, "/", MaxV, "u³");
    -package_stored(CId, Shelf, Weight, Volume, Type)[source(scheduler)];
    !check_shelf_limits(Shelf, NewW, NewV, MaxW, MaxV);
    !check_type_space(Type);
    !calculate_statistics.

@pkg_stored_unknown[atomic]
+package_stored(CId, Shelf, W, V, Type)[source(scheduler)] : total_stored(N) <-
    -+total_stored(N + 1);
    .print("Supervisor: AVISO shelf desconocido ", Shelf, " para ", CId);
    -package_stored(CId, Shelf, W, V, Type)[source(scheduler)].

/* ----------------------------------------------------------------------------
 *  Umbrales de estantería individual: excluir a nivel de asignación
 *  (shelf_excluded_informed garantiza aviso único). Se reutiliza el canal
 *  shelf_near_full aunque hoy nadie lo lea (el scheduler ya no asigna).
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
 * DETECCIÓN DE FALTA DE ESPACIO POR TIPO (70% agregado)
 *   Se suma peso/volumen usado y capacidad total de las estanterías que
 *   admiten Type; si alguna de las dos ratios ≥ 0.7, avisamos al scheduler
 *   con no_space(Type). Una sola vez mientras siga saturado.
 * ============================================================================ */

+!check_type_space(Type) : blocked_type_notified(Type) <- true.

+!check_type_space(Type) :
        type_full_ratio(R) <-
    !sum_type_usage(Type, UW, UV, MW, MV);
    if (MW > 0 & (UW >= MW * R | UV >= MV * R)) {
        +blocked_type_notified(Type);
        .print("Supervisor: tipo ", Type, " al ", UW, "/", MW, "kg (", UV, "/", MV, "u³) ≥ ",
               R*100, "% — avisando scheduler");
        .send(scheduler, tell, no_space(Type))
    }.

+!sum_type_usage(Type, UW, UV, MW, MV) <-
    .findall(used(W, V),
             (shelf_accepts(Type, S) & shelf_usage(S, W, V)),
             UL);
    .findall(cap(MaxW, MaxV),
             (shelf_accepts(Type, S) & shelf_capacity(S, MaxW, MaxV)),
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
 * LIBERACIÓN DE ESPACIO (retrieve / container_exited)
 *   Al sacar un paquete de una estantería, el entorno emite:
 *     - package_retrieved(CId, Shelf, Weight, Volume)  (en la acción retrieve)
 *     - container_exited(CId, Type, Weight, Volume)    (al dropear en salida)
 *   Con esto decrementamos la ocupación y, si la estantería vuelve a estar
 *   por debajo del umbral, desmarcamos y revisamos si el tipo vuelve a tener
 *   espacio (avisando space_available(Type) al scheduler).
 * ============================================================================ */

+package_retrieved(CId, Shelf, Weight, Volume) :
        shelf_usage(Shelf, UW, UV) & shelf_capacity(Shelf, MaxW, MaxV) <-
    NewW = UW - Weight;
    NewV = UV - Volume;
    .abolish(shelf_usage(Shelf, _, _));
    +shelf_usage(Shelf, NewW, NewV);
    .abolish(stored_at(CId, _, _, _, _));
    .print("Supervisor: ", CId, " salió de ", Shelf,
           " | peso ", NewW, "/", MaxW, "kg  vol ", NewV, "/", MaxV, "u³");
    !maybe_unmark(Shelf, NewW, NewV, MaxW, MaxV);
    -package_retrieved(CId, Shelf, Weight, Volume).

+package_retrieved(CId, Shelf, Weight, Volume) <-
    -package_retrieved(CId, Shelf, Weight, Volume).

+container_exited(CId, Type, Weight, Volume) <-
    .print("Supervisor: ", CId, " (", Type, ") ha salido del almacén");
    -container_exited(CId, Type, Weight, Volume).

+!maybe_unmark(Shelf, CurW, CurV, MaxW, MaxV) :
        near_full_ratio(R) &
        CurW < MaxW * R & CurV < MaxV * R &
        shelf_full_marked(Shelf) <-
    -shelf_full_marked(Shelf);
    .send(scheduler, tell, shelf_free(Shelf));
    .print("Supervisor: ", Shelf, " vuelve a tener espacio").

+!maybe_unmark(_, _, _, _, _).

/* El scheduler avisa al terminar el proceso de salida de un tipo para que
 * el supervisor vuelva a poder generar aviso de no_space más adelante. */
+exit_cycle_done(Type)[source(scheduler)] <-
    -blocked_type_notified(Type);
    .print("Supervisor: ciclo de salida del tipo ", Type, " completado");
    -exit_cycle_done(Type)[source(scheduler)].

/* ============================================================================
 * CANDIDATO DE DESALOJO (responde al scheduler en el ciclo de salida)
 *   Elige el primer paquete almacenado de ese tipo.
 * ============================================================================ */

+!request_exit_candidate(Type)[source(scheduler)] :
        stored_at(CId, Shelf, Type, Weight, Volume) <-
    .send(scheduler, tell, exit_candidate(CId, Shelf, Weight, Volume, Type)).

+!request_exit_candidate(Type)[source(scheduler)] <-
    .print("Supervisor: no hay stored_at para tipo ", Type, " — no puedo desalojar");
    .send(scheduler, tell, exit_candidate(none, none, 0, 0, Type)).

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
    .print("ALERTA: El entorno reporta un error de tipo '", ErrorType, "'. Total global acumulado: ", GlobalTotal);
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
    .wait(10000).
    //.stopMAS.

+!check_stop(_) : true <- true.
