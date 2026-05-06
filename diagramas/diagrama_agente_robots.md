flowchart TB

%% =============================================================
%%  DIAGRAMA DE AGENTE PARA LA FAMILIA DE ROBOTS
%%  (robot_light · robot_medium · robot_heavy · robot_heavy2)
%%  Comparten work.asl + mov.asl. Diferencias por miembro:
%%    priority, max_weight, max_size, idlezone,
%%    robot_shelf_priority, faster_capable, is_router_robot
%% =============================================================

AG((("AG  robot")))

%% --- Eventos / percepciones que disparan los planes (entrada) ---
EV_NEW["[EVENT] +container_available(CId,W,H,Wt,Tags)"]
EV_EXIT["[EVENT] +exit_item(CId,Loc,W,V,Tags,Kind)"]
EV_ADL["[EVENT] +active_deadline(short|long)"]
EV_CLAIM["[EVENT] +claim_result(CId, granted|denied)"]
EV_RES["[EVENT] +shelf_reserve / commit / release / retrieved"]
EV_HELP["[EVENT] +help_request / +help_offer / +help_take"]
EV_DESTR["[FFACT] container_destroyed(CId,Tags)"]
EV_AT["[FFACT] at(Me,X,Y) / robot / shelf / container"]

%% --- Tareas/planes principales (planes BDI del robot) ---
T_ENQUEUE["[TASK] !enqueue / !check_idle / !process_next"]
T_HANDLE["[TASK] !handle_container"]
T_CHOOSE["[TASK] !choose_shelf_local + !shelf_fits"]
T_RESERVE["[TASK] !reserve_shelf + peer_broadcast"]
T_DROP["[TASK] !try_drop / !finish_task / !commit_shelf"]
T_NAV["[TASK] !navigate_to / !navigate_to_shelf (mov.asl)"]
T_BLOCK["[TASK] !handle_block (askOne current_priority)"]
T_PICKEX["[TASK] !pick_best_exit_item + claim_exit"]
T_EXEC["[TASK] !execute_exit + !reshelf_carried"]
T_HELP["[TASK] !ask_for_help / !help_take"]
T_HEAVY["[TASK] !decide_heavy_peer / !route_symmetric"]
T_IDLE["[TASK] !go_idle"]
T_RECOV["[TASK] !recover_carrying / -!handle_container"]

%% --- Metas que esos planes intentan cumplir ---
G_STORE(["[GOAL] almacenar_contenedor"])
G_NAV(["[GOAL] navegar_sin_colisiones"])
G_EXIT(["[GOAL] retirar_para_deadline"])
G_HELP(["[GOAL] ceder_o_recibir_ayuda"])
G_ROUTE(["[GOAL] arbitraje_heavy_peer"])
G_IDLE(["[GOAL] volver_a_idlezone"])
G_RECOV(["[GOAL] recuperar_estado"])

%% --- Creencias propias y compartidas ---
F_PRIO["[FACT] priority(P), max_weight, max_size, idlezone"]
F_RPRIO["[FACT] robot_shelf_priority([...])"]
F_ROUTER["[FACT] is_router_robot (heavy y heavy2)"]
F_STATE["[FACT] state(idle|busy|going_idle), container_queue"]
F_USE["[FACT] shelf_usage_local + shelf_reservation"]
F_MYS["[FACT] my_stored / delegated_stored / pending_drop"]
F_NAV["[FACT] moving, prev_pos, visited, block_streak, current_priority"]
F_FRAG["[FACT] carrying_fragile (ralentiza 15%)"]
F_DL["[FACT] active_deadline(Kind), exit_in_progress, pending_claim"]

%% --- Acciones sobre el entorno ---
APP_SEE["[APP] see"]
APP_STEP["[APP] step(NX,NY)"]
APP_PICK["[APP] pickup(CId)"]
APP_DROP["[APP] drop_at(Shelf)"]
APP_DEX["[APP] drop_at_exit(EX,EY)"]
APP_RETR["[APP] retrieve(CId)"]
APP_LOG["[APP] log_event(container_delivered, CId)"]

%% =============================================================
%%  EVENTO ↔ TAREA  (qué dispara qué)
%% =============================================================
EV_NEW   --> T_ENQUEUE
EV_NEW   --> T_HEAVY
EV_EXIT  --> T_PICKEX
EV_ADL   --> T_PICKEX
EV_CLAIM --> T_EXEC
EV_RES   --> F_USE
EV_HELP  --> T_HELP
EV_DESTR --> T_RECOV
EV_AT    --> T_NAV

%% =============================================================
%%  AGENTE → TAREAS
%% =============================================================
AG --- T_ENQUEUE
AG --- T_HANDLE
AG --- T_CHOOSE
AG --- T_RESERVE
AG --- T_DROP
AG --- T_NAV
AG --- T_BLOCK
AG --- T_PICKEX
AG --- T_EXEC
AG --- T_HELP
AG --- T_HEAVY
AG --- T_IDLE
AG --- T_RECOV

%% =============================================================
%%  AGENTE → CREENCIAS
%% =============================================================
AG --- F_PRIO
AG --- F_RPRIO
AG --- F_ROUTER
AG --- F_STATE
AG --- F_USE
AG --- F_MYS
AG --- F_NAV
AG --- F_FRAG
AG --- F_DL

%% =============================================================
%%  TAREA → META  (qué intenta cumplir cada plan)
%% =============================================================
T_ENQUEUE --> G_STORE
T_HANDLE  --> G_STORE
T_CHOOSE  --> G_STORE
T_RESERVE --> G_STORE
T_DROP    --> G_STORE
T_NAV     --> G_NAV
T_BLOCK   --> G_NAV
T_PICKEX  --> G_EXIT
T_EXEC    --> G_EXIT
T_HELP    --> G_HELP
T_HEAVY   --> G_ROUTE
T_IDLE    --> G_IDLE
T_RECOV   --> G_RECOV

%% =============================================================
%%  TAREA → ACCIÓN  (cómo se ejecuta sobre el entorno)
%% =============================================================
T_NAV    --> APP_SEE
T_NAV    --> APP_STEP
T_HANDLE --> APP_PICK
T_DROP   --> APP_DROP
T_EXEC   --> APP_RETR
T_EXEC   --> APP_DEX
T_EXEC   --> APP_LOG
T_RECOV  --> APP_DEX

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
class G_STORE,G_NAV,G_EXIT,G_HELP,G_ROUTE,G_IDLE,G_RECOV goal
class T_ENQUEUE,T_HANDLE,T_CHOOSE,T_RESERVE,T_DROP,T_NAV,T_BLOCK,T_PICKEX,T_EXEC,T_HELP,T_HEAVY,T_IDLE,T_RECOV task
class F_PRIO,F_RPRIO,F_ROUTER,F_STATE,F_USE,F_MYS,F_NAV,F_FRAG,F_DL fact
class EV_NEW,EV_EXIT,EV_ADL,EV_CLAIM,EV_RES,EV_HELP,EV_DESTR,EV_AT event
class APP_SEE,APP_STEP,APP_PICK,APP_DROP,APP_DEX,APP_RETR,APP_LOG app
