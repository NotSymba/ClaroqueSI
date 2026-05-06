flowchart TB

%% =============================================================
%%  DIAGRAMA DE AGENTE PARA TRANSPORT
%%  Camión externo simulado. NO interactúa con el entorno —
%%  solo recibe avisos del scheduler durante cada deadline para
%%  registrar inicio de carga, contenedores cargados y cierre.
%% =============================================================

AG((("AG  transport")))

%% --- Eventos / mensajes que disparan los planes (entrada) ---
EV_LSTART["[EVENT] +load_start(Kind,Group) (scheduler)"]
EV_SHIP["[EVENT] +container_shipped(CId,Tags) (scheduler)"]
EV_LEND["[EVENT] +load_end(Kind,N) (scheduler)"]

%% --- Planes principales del transport ---
T_START["[TASK] !start — anuncia online"]
T_LSTART["[TASK] log de preparación de carga + abolish belief"]
T_SHIP["[TASK] log de contenedor cargado + abolish belief"]
T_LEND["[TASK] log salida del camión + incrementar total_salidas"]

%% --- Metas que persigue el transport ---
G_REGSTART(["[GOAL] registrar_inicio_carga"])
G_REGSHIP(["[GOAL] registrar_container_shipped"])
G_REGEND(["[GOAL] registrar_fin_carga_y_contar_salidas"])

%% --- Creencias del transport ---
F_TOTAL["[FACT] total_salidas(N) — cuenta de deadlines completados"]

%% --- Acciones (no toca el entorno) ---
%% transport.asl no llama a acciones del entorno, solo .print/.abolish.

%% =============================================================
%%  EVENTO ↔ TAREA
%% =============================================================
EV_LSTART --> T_LSTART
EV_SHIP   --> T_SHIP
EV_LEND   --> T_LEND

%% =============================================================
%%  AGENTE → TAREAS
%% =============================================================
AG --- T_START
AG --- T_LSTART
AG --- T_SHIP
AG --- T_LEND

%% =============================================================
%%  AGENTE → CREENCIAS
%% =============================================================
AG --- F_TOTAL

%% =============================================================
%%  TAREA → META
%% =============================================================
T_LSTART --> G_REGSTART
T_SHIP   --> G_REGSHIP
T_LEND   --> G_REGEND

%% Actualización del FACT por el plan de fin
T_LEND   --> F_TOTAL

%% =============================================================
%%  ESTILOS
%% =============================================================
classDef agent fill:#fde2c4,stroke:#a35200,color:#000,stroke-width:2px
classDef goal  fill:#cfe9ff,stroke:#005ea6,color:#000
classDef task  fill:#d4edda,stroke:#155724,color:#000
classDef fact  fill:#fff3cd,stroke:#856404,color:#000
classDef event fill:#f8d7da,stroke:#721c24,color:#000

class AG agent
class G_REGSTART,G_REGSHIP,G_REGEND goal
class T_START,T_LSTART,T_SHIP,T_LEND task
class F_TOTAL fact
class EV_LSTART,EV_SHIP,EV_LEND event
