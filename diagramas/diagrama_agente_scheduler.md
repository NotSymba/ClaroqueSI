flowchart TB

%% =============================================================
%%  DIAGRAMA DE AGENTE PARA EL SCHEDULER
%%  Planificador central. NO asigna shelves a robots — solo
%%  anuncia, cachea info, garantiza accesibilidad y orquesta
%%  el ciclo de salida por deadlines.
%% =============================================================

AG((("AG  scheduler")))

%% --- Eventos / percepciones que disparan los planes (entrada) ---
EV_NEW["[EVENT] +new_container(CId) (entorno)"]
EV_INFO["[EVENT] +container_info(CId,W,H,Wt,Tags) (entorno)"]
EV_GUARD["[EVENT] +guardado(CId,Shelf,W,V) (robot)"]
EV_UNST["[EVENT] +unstorable(CId,Tags) (robot)"]
EV_FORCE["[EVENT] +force_exit_cycle(Tags) (robot)"]
EV_NOSP["[EVENT] +no_space(Group) (supervisor)"]
EV_QLOC["[EVENT] +!provide_location(CId,Requester) (robot)"]
EV_CLAIM["[EVENT] +!claim_exit(CId,Requester) (robot)"]
EV_DONE["[EVENT] +exit_done(CId,Tags) (robot)"]
EV_DESTR["[FFACT] container_destroyed(CId,Tags)"]
EV_CAT["[FFACT] container_at(CId,X,Y) / occupied(X,Y)"]
EV_TIME["[FFACT] (delegado en supervisor para audit temporal)"]

%% --- Planes principales del scheduler ---
T_ACCESS["[TASK] !check_all_packages + !ensure_accessible + !bfs"]
T_RELOC["[TASK] !relocate_safely + relocate_container"]
T_ANNOUNCE["[TASK] !announce_if_allowed (broadcast container_available)"]
T_PROVLOC["[TASK] !provide_location → tell container_location"]
T_RECUNST["[TASK] !record_unstorable + !check_unstorable_threshold"]
T_BEGIN["[TASK] !begin_exit_cycle / !run_one_deadline"]
T_BLOCK["[TASK] !block_group / !unblock_group"]
T_RUNDL["[TASK] !run_deadline (corto urgent / largo normal)"]
T_PUBSTOR["[TASK] !publish_stored_items (pide a supervisor)"]
T_PUBUNST["[TASK] !publish_unstorable_items + !harvest_pending_announce"]
T_PUBEXIT["[TASK] !publish_exit_item (a los 4 robots)"]
T_CLAIM["[TASK] !claim_exit (lock atómico)"]
T_ENDDL["[TASK] !close_deadline + !abolish_all_exit_items"]
T_ENDCYC["[TASK] !end_exit_cycle + !chain_or_release"]
T_FLUSH["[TASK] !flush_all_pending_announce"]
T_GUARD["[TASK] reenviar package_stored al supervisor"]
T_DESTR["[TASK] limpiar referencias container_destroyed"]
T_TRANS["[TASK] tell load_start / load_end / container_shipped a transport"]

%% --- Metas que persigue el scheduler ---
G_ACCESS(["[GOAL] garantizar_accesibilidad_entrada"])
G_INFO(["[GOAL] cachear_info_y_anunciar_a_robots"])
G_LOCSRV(["[GOAL] servir_ubicaciones_a_robots"])
G_TRIGGER(["[GOAL] disparar_ciclo_de_salida"])
G_DEADLINE(["[GOAL] gestionar_deadline_corto_y_largo"])
G_LOCK(["[GOAL] lock_atomico_de_retirada"])
G_NOTIFY(["[GOAL] notificar_transport"])
G_RESET(["[GOAL] limpiar_y_encadenar_pendientes"])

%% --- Creencias del scheduler ---
F_TOPO["[FACT] zone_cell / classification_cell / empty_exit / exit_cell"]
F_SHELF["[FACT] shelf_location(S,X,Y) (9 estanterías)"]
F_TAGS["[FACT] tags_group(Tags,urgent|normal)"]
F_CACHE["[FACT] package_info(CId,Weight,V,Tags)"]
F_PEND_AN["[FACT] pending_announce(CId,...) — grupo bloqueado"]
F_UNST["[FACT] unstorable_pending(Group,List) + threshold(3)"]
F_PEND_EX["[FACT] pending_exit(CId,Loc,W,V,Tags,Kind) + claimed(CId)"]
F_BLOCKED["[FACT] blocked_group(urgent|normal) + active_deadline(Kind)"]
F_TRIG["[FACT] trigger_group(G), exit_cycle_active, pending_queue(Q)"]
F_DT["[FACT] delta_t(30000) — corto=ΔT, largo=3·ΔT"]
F_LOG["[FACT] log_pkg(R,CId,Shelf), deadline_shipped_count(K,N)"]

%% --- Acciones sobre el entorno ---
APP_INFO["[APP] get_container_info(CId)"]
APP_RELOC["[APP] relocate_container(CId,TX,TY)"]
APP_BLK["[APP] block_generation(Group)"]
APP_UNBLK["[APP] unblock_generation(Group)"]
APP_LOG["[APP] log_event(output_phase_started/deadline_started/ended,...)"]

%% =============================================================
%%  EVENTO ↔ TAREA
%% =============================================================
EV_NEW    --> T_ACCESS
EV_NEW    --> APP_INFO
EV_INFO   --> T_ANNOUNCE
EV_QLOC   --> T_PROVLOC
EV_GUARD  --> T_GUARD
EV_UNST   --> T_RECUNST
EV_FORCE  --> T_BEGIN
EV_NOSP   --> T_BEGIN
EV_CLAIM  --> T_CLAIM
EV_DONE   --> T_TRANS
EV_DESTR  --> T_DESTR
EV_CAT    --> T_ACCESS

%% =============================================================
%%  AGENTE → TAREAS
%% =============================================================
AG --- T_ACCESS
AG --- T_RELOC
AG --- T_ANNOUNCE
AG --- T_PROVLOC
AG --- T_RECUNST
AG --- T_BEGIN
AG --- T_BLOCK
AG --- T_RUNDL
AG --- T_PUBSTOR
AG --- T_PUBUNST
AG --- T_PUBEXIT
AG --- T_CLAIM
AG --- T_ENDDL
AG --- T_ENDCYC
AG --- T_FLUSH
AG --- T_GUARD
AG --- T_DESTR
AG --- T_TRANS

%% =============================================================
%%  AGENTE → CREENCIAS
%% =============================================================
AG --- F_TOPO
AG --- F_SHELF
AG --- F_TAGS
AG --- F_CACHE
AG --- F_PEND_AN
AG --- F_UNST
AG --- F_PEND_EX
AG --- F_BLOCKED
AG --- F_TRIG
AG --- F_DT
AG --- F_LOG

%% =============================================================
%%  TAREA → META
%% =============================================================
T_ACCESS  --> G_ACCESS
T_RELOC   --> G_ACCESS
T_ANNOUNCE--> G_INFO
T_FLUSH   --> G_INFO
T_PROVLOC --> G_LOCSRV
T_RECUNST --> G_TRIGGER
T_BEGIN   --> G_TRIGGER
T_BLOCK   --> G_TRIGGER
T_RUNDL   --> G_DEADLINE
T_PUBSTOR --> G_DEADLINE
T_PUBUNST --> G_DEADLINE
T_PUBEXIT --> G_DEADLINE
T_CLAIM   --> G_LOCK
T_TRANS   --> G_NOTIFY
T_GUARD   --> G_NOTIFY
T_ENDDL   --> G_RESET
T_ENDCYC  --> G_RESET
T_DESTR   --> G_RESET

%% =============================================================
%%  TAREA → ACCIÓN
%% =============================================================
T_ACCESS  --> APP_INFO
T_RELOC   --> APP_RELOC
T_BLOCK   --> APP_BLK
T_BLOCK   --> APP_UNBLK
T_RUNDL   --> APP_LOG
T_BEGIN   --> APP_LOG

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
class G_ACCESS,G_INFO,G_LOCSRV,G_TRIGGER,G_DEADLINE,G_LOCK,G_NOTIFY,G_RESET goal
class T_ACCESS,T_RELOC,T_ANNOUNCE,T_PROVLOC,T_RECUNST,T_BEGIN,T_BLOCK,T_RUNDL,T_PUBSTOR,T_PUBUNST,T_PUBEXIT,T_CLAIM,T_ENDDL,T_ENDCYC,T_FLUSH,T_GUARD,T_DESTR,T_TRANS task
class F_TOPO,F_SHELF,F_TAGS,F_CACHE,F_PEND_AN,F_UNST,F_PEND_EX,F_BLOCKED,F_TRIG,F_DT,F_LOG fact
class EV_NEW,EV_INFO,EV_GUARD,EV_UNST,EV_FORCE,EV_NOSP,EV_QLOC,EV_CLAIM,EV_DONE,EV_DESTR,EV_CAT,EV_TIME event
class APP_INFO,APP_RELOC,APP_BLK,APP_UNBLK,APP_LOG app
