/*******************************************************************************
 * SUPERVISOR - Agente de Monitorización y Gestión de Errores
 * 
 * Universidad de Vigo - Sistemas Inteligentes
 * Curso 2025-2026
 * 
 * RESPONSABILIDADES:
 *   1. Monitorizar el estado global del sistema
 *   2. Detectar anomalías y errores
 *   3. Coordinar recuperación de errores
 *   4. Mantener métricas de rendimiento
 *   5. Identificar cuellos de botella
 *   6. Generar reportes y análisis
 * 
 ******************************************************************************/

/* ============================================================================
 * CREENCIAS INICIALES
 * ============================================================================ */

/* Métricas del sistema */
total_errors(0).
errors_by_type(container_too_heavy, 0).
errors_by_type(container_too_big, 0).
errors_by_type(shelf_full, 0).
errors_by_type(illegal_move, 0).
errors_by_type(conflict, 0).
errors_by_type(route_blocked, 0).

/* Tiempos de inicio */
system_start_time(0).

/* Umbral de alerta */
max_errors_per_minute(10).
max_consecutive_errors(100).

/* Añade a tus creencias iniciales */
total_received(0).
total_stored(0).

/* ----------------------------------------------------------------------------
 * CAPACIDAD DE ESTANTERÍAS (replicado de WarehouseModel.initializeShelves)
 *   shelf_capacity(Id, MaxWeight, MaxVolume)
 *   shelf_usage(Id, CurWeight, CurVolume)   — acumulado que mantenemos aquí
 * -------------------------------------------------------------------------- */
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

/* Umbral de "casi lleno" (90%) para avisar antes de rebasar */
near_full_ratio(0.9).

!start.

+!start : true <-
    .print("Supervisor iniciado y monitorizando el almacén...").

+new_container(CId) : total_received(N) <-
    -+total_received(N+1);
    .print("Nuevo contenedor detectado por supervisor. Total recibidos: ", N+1).

/* ----------------------------------------------------------------------------
 * LOG DE PAQUETES DESDE SCHEDULER
 * -------------------------------------------------------------------------- */

+package_arrived(CId, Weight, Volume, Type)[source(scheduler)] <-
    .print("Supervisor: registrado ", CId, " peso=", Weight, " vol=", Volume, " tipo=", Type);
    -package_arrived(CId, Weight, Volume, Type)[source(scheduler)].

/* ----------------------------------------------------------------------------
 * PAQUETE ALMACENADO — actualiza ocupación de la estantería y verifica límites.
 * El scheduler reenvía el mensaje del robot con el peso y volumen del paquete.
 * -------------------------------------------------------------------------- */

@pkg_stored_known[atomic]
+package_stored(CId, Shelf, Weight, Volume)[source(scheduler)] :
        shelf_capacity(Shelf, MaxW, MaxV) & shelf_usage(Shelf, UW, UV) &
        total_stored(N) <-
    NewW = UW + Weight;
    NewV = UV + Volume;
    .abolish(shelf_usage(Shelf, _, _));
    +shelf_usage(Shelf, NewW, NewV);
    .abolish(total_stored(_));
    +total_stored(N + 1);
    .print("Supervisor: ", CId, " → ", Shelf,
           " | peso ", NewW, "/", MaxW, "kg  vol ", NewV, "/", MaxV, "u³");
    -package_stored(CId, Shelf, Weight, Volume)[source(scheduler)];
    !check_shelf_limits(Shelf, NewW, NewV, MaxW, MaxV);
    !calculate_statistics.

/* Estantería desconocida — avisa y registra igualmente el total almacenado */
@pkg_stored_unknown[atomic]
+package_stored(CId, Shelf, W, V)[source(scheduler)] : total_stored(N) <-
    .abolish(total_stored(_));
    +total_stored(N + 1);
    .print("Supervisor: AVISO shelf desconocido ", Shelf, " para ", CId);
    -package_stored(CId, Shelf, W, V)[source(scheduler)].

/* Verificación de límites. Al rebasar máximo o al cruzar el 90% se avisa al
 * scheduler una sola vez (shelf_excluded_informed) para que deje de asignarla. */
+!check_shelf_limits(Shelf, CurW, _, MaxW, _) : CurW > MaxW <-
    .print("¡ALERTA! ", Shelf, " REBASÓ peso: ", CurW, "/", MaxW, "kg");
    !notify_exclusion(Shelf).

+!check_shelf_limits(Shelf, _, CurV, _, MaxV) : CurV > MaxV <-
    .print("¡ALERTA! ", Shelf, " REBASÓ volumen: ", CurV, "/", MaxV, "u³");
    !notify_exclusion(Shelf).

+!check_shelf_limits(Shelf, CurW, _, MaxW, _) :
        near_full_ratio(R) & CurW >= MaxW * R <-
    .print("Supervisor: ", Shelf, " casi al tope en peso (", CurW, "/", MaxW, "kg)");
    !notify_exclusion(Shelf).

+!check_shelf_limits(Shelf, _, CurV, _, MaxV) :
        near_full_ratio(R) & CurV >= MaxV * R <-
    .print("Supervisor: ", Shelf, " casi al tope en volumen (", CurV, "/", MaxV, "u³)");
    !notify_exclusion(Shelf).

+!check_shelf_limits(_, _, _, _, _).

/* Notifica al scheduler una sola vez que la estantería debe excluirse */
+!notify_exclusion(Shelf) : not shelf_excluded_informed(Shelf) <-
    +shelf_excluded_informed(Shelf);
    .send(scheduler, tell, shelf_near_full(Shelf));
    .print("Supervisor: notificado scheduler → excluir ", Shelf).

+!notify_exclusion(_).

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
    .wait(10000);
    .stopMAS.

+!check_stop(Total) : true <-
    true.

/* ============================================================================
 * CONSULTA DE CAPACIDAD — el scheduler pregunta si una estantería admite un
 * paquete de peso W y volumen V. Se responde con can_store_reply(CId,Shelf,YN).
 * ============================================================================ */

+can_store(CId, Shelf, W, V)[source(scheduler)] :
        shelf_capacity(Shelf, MaxW, MaxV) & shelf_usage(Shelf, UW, UV) &
        UW + W <= MaxW & UV + V <= MaxV <-
    .send(scheduler, tell, can_store_reply(CId, Shelf, yes));
    -can_store(CId, Shelf, W, V)[source(scheduler)].

+can_store(CId, Shelf, W, V)[source(scheduler)] <-
    .send(scheduler, tell, can_store_reply(CId, Shelf, no));
    -can_store(CId, Shelf, W, V)[source(scheduler)].

