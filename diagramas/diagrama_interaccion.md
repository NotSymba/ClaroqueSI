flowchart LR

%% =====================================================
%%  AGENTES
%% =====================================================
AG_SCHED["[AG] scheduler"]
AG_SUP["[AG] supervisor"]
AG_ROB["[AG] Robots<br>(robot_light, robot_medium,<br>robot_heavy, robot_heavy2)"]
AG_TRA["[AG] transport"]

%% =====================================================
%%  INTERACCIONES GLOBALES (rectángulos redondeados)
%% =====================================================
INT_STORE(["[INT] Almacenamiento de contenedores"])
INT_SAT(["[INT] Saturación / control de shelves"])
INT_EXIT(["[INT] Ciclo de salida por deadlines"])
INT_NAV(["[INT] Navegación cooperativa"])
INT_HEAVY(["[INT] Arbitraje heavy ↔ heavy2"])

%% Iniciadores de cada interacción (.send/.broadcast en el código)
AG_SCHED -- starts --> INT_STORE
AG_SUP   -- starts --> INT_SAT
AG_SCHED -- starts --> INT_EXIT
AG_ROB   -- starts --> INT_NAV
AG_ROB   -- starts --> INT_HEAVY

%% =====================================================
%%  CONVERSACIONES (hexágonos)
%% =====================================================

%% --- Almacenamiento ---
INT_STORE --> CONV_ANN{{"[CONV] anuncio_contenedor"}}
INT_STORE --> CONV_LOC{{"[CONV] consulta_ubicacion"}}
INT_STORE --> CONV_RES{{"[CONV] reserva_shelf_p2p"}}
INT_STORE --> CONV_GUARD{{"[CONV] confirmacion_guardado"}}
INT_STORE --> CONV_UNST{{"[CONV] unstorable"}}
INT_STORE --> CONV_DESTR{{"[CONV] limpieza_destruido"}}

%% --- Saturación ---
INT_SAT --> CONV_NOSP{{"[CONV] aviso_70_porciento"}}
INT_SAT --> CONV_SHELF{{"[CONV] estado_shelf"}}
INT_SAT --> CONV_SNAP{{"[CONV] snapshot_uso_autoritativo"}}

%% --- Ciclo de salida ---
INT_EXIT --> CONV_DLINE{{"[CONV] inicio_fin_deadline"}}
INT_EXIT --> CONV_LIST{{"[CONV] lista_stored_por_grupo"}}
INT_EXIT --> CONV_PUB{{"[CONV] publicacion_exit_item"}}
INT_EXIT --> CONV_CLAIM{{"[CONV] claim_exit"}}
INT_EXIT --> CONV_DONE{{"[CONV] exit_done"}}
INT_EXIT --> CONV_HELP{{"[CONV] ayuda_peer_al_mas_pesado"}}
INT_EXIT --> CONV_TRA{{"[CONV] notificacion_transport"}}

%% --- Navegación ---
INT_NAV --> CONV_PRIO{{"[CONV] consulta_prioridad_paso"}}

%% --- Heavy ---
INT_HEAVY --> CONV_ROUTE{{"[CONV] route_symmetric"}}

%% =====================================================
%%  MENSAJES (rectángulos simples)
%% =====================================================

%% ---------- ALMACENAMIENTO ----------

%% anuncio_contenedor
M_PA["[MSG] tell package_arrived(CId,Weight,V,Tags)"]
M_NEW["[MSG] tell container_available(CId,W,H,Weight,Tags)"]
M_NEWUNT["[MSG] broadcast untell container_available(CId,_,_,_,_)"]

AG_SCHED -.-> M_PA
M_PA -.-> CONV_ANN
CONV_ANN -.-> AG_SUP

AG_SCHED -.-> M_NEW
M_NEW -.-> CONV_ANN
CONV_ANN -.-> AG_ROB

AG_SCHED -.-> M_NEWUNT
M_NEWUNT -.-> CONV_DESTR
CONV_DESTR -.-> AG_ROB

%% consulta_ubicacion
M_QLOC["[MSG] achieve provide_location(CId,Me)"]
M_LOC["[MSG] tell container_location(CId,X,Y)"]

AG_ROB -.-> M_QLOC
M_QLOC -.-> CONV_LOC
CONV_LOC -.-> AG_SCHED

AG_SCHED -.-> M_LOC
M_LOC -.-> CONV_LOC
CONV_LOC -.-> AG_ROB

%% reserva_shelf_p2p
M_RES["[MSG] tell shelf_reserve(CId,Shelf,W,V)"]
M_COMM["[MSG] tell shelf_commit(CId,Shelf,W,V)"]
M_RLS["[MSG] tell shelf_release(CId,Shelf,W,V)"]
M_RET["[MSG] tell shelf_retrieved(CId,Shelf,W,V)"]

AG_ROB -.-> M_RES
M_RES -.-> CONV_RES
AG_ROB -.-> M_COMM
M_COMM -.-> CONV_RES
AG_ROB -.-> M_RLS
M_RLS -.-> CONV_RES
AG_ROB -.-> M_RET
M_RET -.-> CONV_RES
CONV_RES -.-> AG_ROB

%% confirmacion_guardado
M_GUARD["[MSG] tell guardado(CId,Shelf,W,V)"]
M_GUARDL["[MSG] tell guardado(CId,Shelf) (legacy)"]
M_PSTO["[MSG] tell package_stored(CId,Shelf,W,V,Tags)"]

AG_ROB -.-> M_GUARD
M_GUARD -.-> CONV_GUARD
AG_ROB -.-> M_GUARDL
M_GUARDL -.-> CONV_GUARD
CONV_GUARD -.-> AG_SCHED

AG_SCHED -.-> M_PSTO
M_PSTO -.-> CONV_GUARD
CONV_GUARD -.-> AG_SUP

%% unstorable
M_UNST["[MSG] tell unstorable(CId,Tags)"]

AG_ROB -.-> M_UNST
M_UNST -.-> CONV_UNST
CONV_UNST -.-> AG_SCHED

%% ---------- SATURACIÓN ----------

%% aviso_70_porciento
M_NOSP["[MSG] tell no_space(Group)"]
AG_SUP -.-> M_NOSP
M_NOSP -.-> CONV_NOSP
CONV_NOSP -.-> AG_SCHED

%% estado_shelf
M_SFULL["[MSG] tell shelf_full(Shelf)"]
M_SFREE["[MSG] tell shelf_free(Shelf)"]
AG_SUP -.-> M_SFULL
M_SFULL -.-> CONV_SHELF
AG_SUP -.-> M_SFREE
M_SFREE -.-> CONV_SHELF
CONV_SHELF -.-> AG_SCHED

%% snapshot_uso_autoritativo
M_SNAP["[MSG] tell shelf_usage_snapshot(L)"]
AG_SUP -.-> M_SNAP
M_SNAP -.-> CONV_SNAP
CONV_SNAP -.-> AG_ROB

%% ---------- CICLO DE SALIDA ----------

%% inicio_fin_deadline
M_ECSTA["[MSG] tell exit_cycle_started"]
M_DLST["[MSG] tell deadline_started(Kind,Group,Duration)"]
M_ADL["[MSG] broadcast tell active_deadline(Kind)"]
M_ADLU["[MSG] broadcast untell active_deadline(Kind)"]
M_ECEND["[MSG] tell exit_cycle_ended(Group)"]

AG_SCHED -.-> M_ECSTA
M_ECSTA -.-> CONV_DLINE
AG_SCHED -.-> M_DLST
M_DLST -.-> CONV_DLINE
AG_SCHED -.-> M_ECEND
M_ECEND -.-> CONV_DLINE
CONV_DLINE -.-> AG_SUP

AG_SCHED -.-> M_ADL
M_ADL -.-> CONV_DLINE
AG_SCHED -.-> M_ADLU
M_ADLU -.-> CONV_DLINE
CONV_DLINE -.-> AG_ROB

%% lista_stored_por_grupo
M_LREQ["[MSG] achieve list_stored(Group,Kind)"]
M_LRSP["[MSG] tell stored_list_response(Kind,L)"]

AG_SCHED -.-> M_LREQ
M_LREQ -.-> CONV_LIST
CONV_LIST -.-> AG_SUP
AG_SUP -.-> M_LRSP
M_LRSP -.-> CONV_LIST
CONV_LIST -.-> AG_SCHED

%% publicacion_exit_item
M_EXIT["[MSG] tell exit_item(CId,Loc,W,V,Tags,Kind)"]
M_EXIT_U["[MSG] broadcast untell exit_item(CId,Loc,W,V,Tags,Kind)"]
M_EXTK["[MSG] broadcast tell exit_taken(CId)"]
M_EXTKU["[MSG] broadcast untell exit_taken(CId)"]

AG_SCHED -.-> M_EXIT
M_EXIT -.-> CONV_PUB
AG_SCHED -.-> M_EXIT_U
M_EXIT_U -.-> CONV_PUB
AG_SCHED -.-> M_EXTK
M_EXTK -.-> CONV_PUB
AG_SCHED -.-> M_EXTKU
M_EXTKU -.-> CONV_PUB
CONV_PUB -.-> AG_ROB

%% claim_exit
M_CLAIM["[MSG] achieve claim_exit(CId,Me)"]
M_CRES["[MSG] tell claim_result(CId, granted | denied)"]

AG_ROB -.-> M_CLAIM
M_CLAIM -.-> CONV_CLAIM
CONV_CLAIM -.-> AG_SCHED
AG_SCHED -.-> M_CRES
M_CRES -.-> CONV_CLAIM
CONV_CLAIM -.-> AG_ROB

%% exit_done
M_EDONE["[MSG] tell exit_done(CId,Tags)"]
M_FORCE["[MSG] tell force_exit_cycle(Tags)"]

AG_ROB -.-> M_EDONE
M_EDONE -.-> CONV_DONE
AG_ROB -.-> M_FORCE
M_FORCE -.-> CONV_DONE
CONV_DONE -.-> AG_SCHED

%% ayuda_peer_al_mas_pesado
M_HREQ["[MSG] tell help_request(Asker,MaxW)"]
M_HOFF["[MSG] tell help_offer(CId,Shelf,W,V,Tags)"]
M_HTAKE["[MSG] achieve help_take(Asker,CId)"]
M_HCONF["[MSG] tell help_confirm(CId,Sh,CW,CV,Tags)"]
M_HDENY["[MSG] tell help_deny(CId)"]

AG_ROB -.-> M_HREQ
M_HREQ -.-> CONV_HELP
AG_ROB -.-> M_HOFF
M_HOFF -.-> CONV_HELP
AG_ROB -.-> M_HTAKE
M_HTAKE -.-> CONV_HELP
AG_ROB -.-> M_HCONF
M_HCONF -.-> CONV_HELP
AG_ROB -.-> M_HDENY
M_HDENY -.-> CONV_HELP
CONV_HELP -.-> AG_ROB

%% notificacion_transport
M_LSTART["[MSG] tell load_start(Kind,Group)"]
M_LEND["[MSG] tell load_end(Kind,N)"]
M_SHIP["[MSG] tell container_shipped(CId,Tags)"]

AG_SCHED -.-> M_LSTART
M_LSTART -.-> CONV_TRA
AG_SCHED -.-> M_LEND
M_LEND -.-> CONV_TRA
AG_SCHED -.-> M_SHIP
M_SHIP -.-> CONV_TRA
CONV_TRA -.-> AG_TRA

%% ---------- NAVEGACIÓN ----------

%% consulta_prioridad_paso
M_PRIO["[MSG] askOne current_priority(_) (timeout 200ms)"]

AG_ROB -.-> M_PRIO
M_PRIO -.-> CONV_PRIO
CONV_PRIO -.-> AG_ROB

%% ---------- HEAVY ----------

%% route_symmetric
M_RHI["[MSG] achieve report_heavy_info(Me)"]
M_HPI["[MSG] tell heavy_peer_info(QueueLen,State)"]

AG_ROB -.-> M_RHI
M_RHI -.-> CONV_ROUTE
AG_ROB -.-> M_HPI
M_HPI -.-> CONV_ROUTE
CONV_ROUTE -.-> AG_ROB

%% =====================================================
%%  ESTILOS
%% =====================================================
classDef agent       fill:#cce5ff,stroke:#004085,color:#000
classDef interaction fill:#d4edda,stroke:#155724,color:#000
classDef conv        fill:#fff3cd,stroke:#856404,color:#000
classDef msg         fill:#f8d7da,stroke:#721c24,color:#000

class AG_SCHED,AG_SUP,AG_ROB,AG_TRA agent
class INT_STORE,INT_SAT,INT_EXIT,INT_NAV,INT_HEAVY interaction
class CONV_ANN,CONV_LOC,CONV_RES,CONV_GUARD,CONV_UNST,CONV_DESTR,CONV_NOSP,CONV_SHELF,CONV_SNAP,CONV_DLINE,CONV_LIST,CONV_PUB,CONV_CLAIM,CONV_DONE,CONV_HELP,CONV_TRA,CONV_PRIO,CONV_ROUTE conv
class M_PA,M_NEW,M_NEWUNT,M_QLOC,M_LOC,M_RES,M_COMM,M_RLS,M_RET,M_GUARD,M_GUARDL,M_PSTO,M_UNST,M_NOSP,M_SFULL,M_SFREE,M_SNAP,M_ECSTA,M_DLST,M_ADL,M_ADLU,M_ECEND,M_LREQ,M_LRSP,M_EXIT,M_EXIT_U,M_EXTK,M_EXTKU,M_CLAIM,M_CRES,M_EDONE,M_FORCE,M_HREQ,M_HOFF,M_HTAKE,M_HCONF,M_HDENY,M_LSTART,M_LEND,M_SHIP,M_PRIO,M_RHI,M_HPI msg
