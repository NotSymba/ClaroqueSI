/*******************************************************************************
 * TRANSPORT - Agente de transporte externo (simulado)
 *
 * Representa al camión / transportista que recoge los contenedores al final
 * de cada deadline de salida. No interactúa con el entorno: sólo recibe los
 * avisos del scheduler para registrar qué se está transportando.
 *
 *   load_start(DeadlineKind, TypeList)   → preparando el transporte
 *   container_shipped(CId, Type)         → contenedor cargado en el camión
 *   load_end(DeadlineKind, Count)        → el camión se va con N contenedores
 ******************************************************************************/
total_salidas(0).
!start.

+!start <-
    .print("Transport online — listo para recoger contenedores en los deadlines de salida.").

+load_start(Kind, Types)[source(scheduler)] <-
    .print("Transport: preparando carga '", Kind, "' para tipos ", Types);
    .abolish(load_start(Kind, Types)[source(scheduler)]).

+container_shipped(CId, Type)[source(scheduler)] <-
    .print("Transport: cargado ", CId, " (", Type, ")");
    .abolish(container_shipped(CId, Type)[source(scheduler)]).

+load_end(Kind, N)[source(scheduler)] : total_salidas(T)<-
    .print("Transport: sale el camión de '", Kind, "' con ", N, " contenedores");
    .abolish(load_end(Kind, N)[source(scheduler)]);
    -total_salidas(T);
    +total_salidas(T+1).
