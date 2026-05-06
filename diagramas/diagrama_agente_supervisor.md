flowchart TB

%% =============================================================
%%  DIAGRAMA DE AGENTE PARA EL SUPERVISOR
%%  Monitor de ocupación REAL de shelves, métricas, detección
%%  de saturación al 70 % por grupo y vigilancia temporal de
%%  deadlines. Sirve listas de stored al scheduler.
%% =============================================================

AG((("AG  supervisor")))

%% --- Eventos / percepciones que disparan los planes (entrada) ---
EV_PA["[EVENT] +package_arrived(CId,W,V,Tags) (scheduler)"]
EV_PSTO["[EVENT] +package_stored(CId,Shelf,W,V,Tags) (scheduler)"]
EV_PRET["[FFACT] package_retrieved(CId,Shelf,W,V) (entorno)"]
EV_EXIT["[FFACT] container_exited(CId,Tags,W,V)"]
EV_DESTR["[FFACT] container_destroyed(CId,Tags)"]
EV_LSTREQ["[EVENT] +!list_stored(Group,Kind) (scheduler)"]
EV_DLST["[EVENT] +deadline_started(Kind,Group,Duration) (scheduler)"]
EV_ECEND["[EVENT] +exit_cycle_started / +exit_cycle_ended (scheduler)"]
EV_RSTAT["[EVENT] +robot_status(State) (robots)"]
EV_TERR["[FFACT] total_errors(ErrorType,GlobalTotal) (entorno)"]
EV_TIME["[FFACT] current_time(T) (tras get_time)"]
EV_NEWC["[FFACT] new_container(CId)"]

%% --- Planes principales del supervisor ---
T_REGIN["[TASK] registrar at_warehouse(CId,Tags,W,V)"]
T_RECOMP["[TASK] !recompute_shelf_usage + +stored_at"]
T_LIMIT["[TASK] !check_shelf_limits + !mark_full / !maybe_unmark"]
T_GROUP["[TASK] !check_group_space + !sum_group_usage (70%)"]
T_SNAP["[TASK] !!periodic_snapshot + !broadcast_usage_snapshot"]
T_LIST["[TASK] !list_stored → tell stored_list_response"]
T_DLWIN["[TASK] crear deadline_window(Kind,Group,Tstart,Tend)"]
T_AUDIT["[TASK] !!periodic_deadline_audit + !audit_windows"]
T_REPORT["[TASK] !audit_deadline_expired + log deadline_missed"]
T_PURGE["[TASK] !purge_windows_of(Group)"]
T_RETR["[TASK] limpiar stored_at tras package_retrieved"]
T_DESTR["[TASK] limpiar at_warehouse tras container_destroyed"]
T_STATS["[TASK] !calculate_statistics"]
T_ERR["[TASK] +total_errors → !update_specific_error + !check_stop"]
T_RSTAT["[TASK] +status_of(Robot,State)"]
T_T0["[TASK] fijar system_start_time(T0) con get_time"]

%% --- Metas que persigue el supervisor ---
G_USAGE(["[GOAL] mantener_shelf_usage_autoritativo"])
G_SHARE(["[GOAL] difundir_snapshot_a_robots"])
G_SAT(["[GOAL] detectar_saturacion_70_y_avisar"])
G_LIMITS(["[GOAL] alertar_shelf_individual_casi_llena"])
G_LIST(["[GOAL] proveer_lista_stored_al_scheduler"])
G_DLAUDIT(["[GOAL] auditar_deadlines_temporales"])
G_METRICS(["[GOAL] llevar_metricas_y_errores"])
G_STOP(["[GOAL] parar_MAS_si_errores_excesivos"])

%% --- Creencias del supervisor ---
F_CAP["[FACT] shelf_capacity(S,MaxW,MaxV) — 9 estanterías"]
F_USE["[FACT] shelf_usage(S,W,V) AUTORITATIVO"]
F_GROUP["[FACT] urgent_shelf / regular_shelf + tags_group"]
F_RATIO["[FACT] near_full_ratio(0.9), type_full_ratio(0.7)"]
F_STORED["[FACT] stored_at(CId,Shelf,Tags,W,V) + at_warehouse"]
F_FULLMK["[FACT] shelf_full_marked(S), blocked_group_notified(G)"]
F_DLW["[FACT] deadline_window(Kind,Group,Ts,Te) + audited"]
F_METRIC["[FACT] total_received, total_stored, deadline_violations"]
F_ERR["[FACT] total_errors / errors_by_type / max_consecutive_errors"]
F_PERIOD["[FACT] snapshot_period_ms(15000), deadline_audit_period_ms(2000)"]
F_T0["[FACT] system_start_time(T0)"]
F_RSTAT["[FACT] status_of(Robot,State)"]

%% --- Acciones sobre el entorno ---
APP_TIME["[APP] get_time → current_time(T)"]
APP_LOG["[APP] log_event(no_space_detected | deadline_missed, ...)"]
APP_STOP["[APP] .stopMAS (caso crítico)"]

%% =============================================================
%%  EVENTO ↔ TAREA
%% =============================================================
EV_PA   --> T_REGIN
EV_PSTO --> T_RECOMP
EV_PSTO --> T_LIMIT
EV_PSTO --> T_GROUP
EV_PSTO --> T_SNAP
EV_PSTO --> T_STATS
EV_PRET --> T_RETR
EV_PRET --> T_RECOMP
EV_PRET --> T_LIMIT
EV_EXIT --> T_DESTR
EV_DESTR--> T_DESTR
EV_LSTREQ --> T_LIST
EV_DLST --> T_DLWIN
EV_ECEND --> T_PURGE
EV_RSTAT --> T_RSTAT
EV_TERR --> T_ERR
EV_TIME --> T_AUDIT
EV_NEWC --> F_METRIC

%% =============================================================
%%  AGENTE → TAREAS
%% =============================================================
AG --- T_REGIN
AG --- T_RECOMP
AG --- T_LIMIT
AG --- T_GROUP
AG --- T_SNAP
AG --- T_LIST
AG --- T_DLWIN
AG --- T_AUDIT
AG --- T_REPORT
AG --- T_PURGE
AG --- T_RETR
AG --- T_DESTR
AG --- T_STATS
AG --- T_ERR
AG --- T_RSTAT
AG --- T_T0

%% =============================================================
%%  AGENTE → CREENCIAS
%% =============================================================
AG --- F_CAP
AG --- F_USE
AG --- F_GROUP
AG --- F_RATIO
AG --- F_STORED
AG --- F_FULLMK
AG --- F_DLW
AG --- F_METRIC
AG --- F_ERR
AG --- F_PERIOD
AG --- F_T0
AG --- F_RSTAT

%% =============================================================
%%  TAREA → META
%% =============================================================
T_REGIN  --> G_USAGE
T_RECOMP --> G_USAGE
T_RETR   --> G_USAGE
T_DESTR  --> G_USAGE
T_SNAP   --> G_SHARE
T_GROUP  --> G_SAT
T_LIMIT  --> G_LIMITS
T_LIST   --> G_LIST
T_DLWIN  --> G_DLAUDIT
T_AUDIT  --> G_DLAUDIT
T_REPORT --> G_DLAUDIT
T_PURGE  --> G_DLAUDIT
T_STATS  --> G_METRICS
T_RSTAT  --> G_METRICS
T_T0     --> G_METRICS
T_ERR    --> G_STOP

%% =============================================================
%%  TAREA → ACCIÓN
%% =============================================================
T_T0     --> APP_TIME
T_DLWIN  --> APP_TIME
T_AUDIT  --> APP_TIME
T_GROUP  --> APP_LOG
T_REPORT --> APP_LOG
T_ERR    --> APP_STOP

%% =============================================================
%%  ESTILOS
%% =============================================================
classDef agent fill:#fde2c4,stroke:#a35200,color:#000,stroke-width:2px
classDef goal  fill:#cfe9ff,stroke:#005ea6,color:#000
classDef task  fill:#d4edda,stroke:#155724,color:#000
classDef fact  fill:#fff3cd,stroke:#856404,color:#000
classDef event fill:#f8d7da,stroke:#721c24,color:#000
classDef app   fill:#e2d6f3,stroke:#4b2e83,color:#000

class AG agent
class G_USAGE,G_SHARE,G_SAT,G_LIMITS,G_LIST,G_DLAUDIT,G_METRICS,G_STOP goal
class T_REGIN,T_RECOMP,T_LIMIT,T_GROUP,T_SNAP,T_LIST,T_DLWIN,T_AUDIT,T_REPORT,T_PURGE,T_RETR,T_DESTR,T_STATS,T_ERR,T_RSTAT,T_T0 task
class F_CAP,F_USE,F_GROUP,F_RATIO,F_STORED,F_FULLMK,F_DLW,F_METRIC,F_ERR,F_PERIOD,F_T0,F_RSTAT fact
class EV_PA,EV_PSTO,EV_PRET,EV_EXIT,EV_DESTR,EV_LSTREQ,EV_DLST,EV_ECEND,EV_RSTAT,EV_TERR,EV_TIME,EV_NEWC event
class APP_TIME,APP_LOG,APP_STOP app
