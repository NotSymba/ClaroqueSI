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
max_consecutive_errors(5).

/* Añade a tus creencias iniciales */
total_received(0).
total_stored(0).

!start.

+!start : true <-
    .print("Supervisor iniciado y monitorizando el almacén...").

+new_container(CId) : total_received(N) <-
    -+total_received(N+1);
    .print("Nuevo contenedor detectado por supervisor. Total recibidos: ", N+1).


+container_stored(CId, ShelfId)[source(Robot)] : total_stored(N) <-
    -+total_stored(N+1);
    .print("Supervisor anota: ", Robot, " almacenó ", CId, " en ", ShelfId, ". Total almacenados: ", N+1);
    !calculate_statistics.

+!calculate_statistics : total_received(R) & total_stored(S) & R > 0 <-
    SuccessRate = (S / R) * 100;
    .print("--- ESTADÍSTICAS GLOBALES ---");
    .print("Recibidos: ", R, " | Almacenados: ", S, " | Tasa de éxito: ", SuccessRate, "%").


+robot_status(State)[source(Robot)] <-
    -+status_of(Robot, State);
    .print("Monitor: El robot ", Robot, " ha cambiado su estado a ", State).


+total_errors(ErrorType, GlobalTotal) <-
    -+total_errors(GlobalTotal);
    
    !update_specific_error(ErrorType);
    
    .print("ALERTA: El entorno reporta un error de tipo '", ErrorType, "'. Total global acumulado: ", GlobalTotal);
    
    !check_stop(GlobalTotal).

+!update_specific_error(Type) : errors_by_type(Type, OldCount) <-
    -+errors_by_type(Type, OldCount + 1).

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

