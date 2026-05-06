flowchart TB

%% =====================================================
%%  RAÍZ
%% =====================================================
GOAL_MAIN(["[GOAL] gestionar_almacen_inteligente"])

GOAL_MAIN --> AND_ROOT{{"AND"}}
AND_ROOT --> GOAL_STORE(["[GOAL] almacenar_contenedores_entrantes"])
AND_ROOT --> GOAL_EXIT(["[GOAL] liberar_espacio_por_deadline"])
AND_ROOT --> GOAL_AVOID(["[GOAL] evitar_saturacion_estanterias"])
AND_ROOT --> GOAL_NAV(["[GOAL] navegar_sin_colisiones"])
AND_ROOT --> GOAL_TRANS(["[GOAL] registrar_envio_externo"])

%% =====================================================
%%  ALMACENAR (scheduler + robots)
%% =====================================================
GOAL_STORE --> AND_STORE{{"AND"}}
AND_STORE --> GOAL_ANNOUNCE(["[GOAL] anunciar_contenedor_disponible"])
AND_STORE --> GOAL_DECIDE_MGR(["[GOAL] decidir_si_puedo_gestionar"])
AND_STORE --> GOAL_ENQUEUE(["[GOAL] encolar_contenedor"])
AND_STORE --> GOAL_PROCESS(["[GOAL] procesar_siguiente_contenedor"])

GOAL_ANNOUNCE --> AND_ANN{{"AND"}}
AND_ANN --> GOAL_CHECK_ACC(["[GOAL] verificar_accesibilidad_entrada"])
AND_ANN --> GOAL_BCAST_NEW(["[GOAL] broadcast container_available"])
GOAL_CHECK_ACC --> GOAL_BFS(["[GOAL] bfs_accesibilidad"])
GOAL_CHECK_ACC --> GOAL_RELOC(["[GOAL] reubicar_contenedor_atrapado"])

GOAL_DECIDE_MGR --> GOAL_CAN_MNG(["[GOAL] can_i_manage"])
GOAL_DECIDE_MGR --> GOAL_FASTER(["[GOAL] not_faster_capable"])

GOAL_ENQUEUE --> GOAL_PRIO_URG(["[GOAL] prioridad_a_la_cabeza_si_urgent"])

GOAL_PROCESS --> AND_PROC{{"AND"}}
AND_PROC --> GOAL_QUERY_LOC(["[GOAL] query_location"])
AND_PROC --> GOAL_CHOOSE(["[GOAL] choose_shelf_local"])
AND_PROC --> GOAL_RESERVE(["[GOAL] reservar_estanteria"])
AND_PROC --> GOAL_GOTO_PKG(["[GOAL] go_to_contenedor"])
AND_PROC --> GOAL_PICKUP(["[GOAL] pickup"])
AND_PROC --> GOAL_MARK_FR(["[GOAL] mark_fragile_if"])
AND_PROC --> GOAL_NAV_SHELF(["[GOAL] navegar_a_estanteria"])
AND_PROC --> GOAL_DROP(["[GOAL] depositar_try_drop"])
AND_PROC --> GOAL_UNSTOR(["[GOAL] avisar_unstorable_si_no_cabe"])

GOAL_CHOOSE --> AND_CH{{"AND"}}
AND_CH --> GOAL_FITS(["[GOAL] check_stock_capacidad_shelf_fits"])
AND_CH --> GOAL_LOCAL_USE(["[GOAL] consultar_shelf_usage_local"])
AND_CH --> GOAL_FILTER(["[GOAL] filter_first_fitting"])

GOAL_RESERVE --> GOAL_BCAST_RES(["[GOAL] peer_broadcast_shelf_reserve"])
GOAL_GOTO_PKG --> GOAL_VERIFY_POS(["[GOAL] verify_position"])
GOAL_DROP --> GOAL_COMMIT(["[GOAL] commit_shelf"])
GOAL_DROP --> GOAL_NOTIFY_GUARD(["[GOAL] notificar_guardado_al_scheduler"])

%% =====================================================
%%  CICLO DE SALIDA POR DEADLINES
%% =====================================================
GOAL_EXIT --> AND_EXIT{{"AND"}}
AND_EXIT --> GOAL_TRIG(["[GOAL] disparar_begin_exit_cycle"])
AND_EXIT --> GOAL_PUBLISH(["[GOAL] publicar_exit_items"])
AND_EXIT --> GOAL_PICK_EX(["[GOAL] pick_best_exit_item"])
AND_EXIT --> GOAL_CLAIM(["[GOAL] claim_exit_lock_atomico"])
AND_EXIT --> GOAL_EXEC_EX(["[GOAL] execute_exit"])
AND_EXIT --> GOAL_HELP(["[GOAL] protocolo_ayuda_peer"])
AND_EXIT --> GOAL_RESHELF(["[GOAL] reshelf_carried_si_deadline_cerrado"])
AND_EXIT --> GOAL_CLOSE(["[GOAL] close_deadline_y_unblock_group"])

GOAL_TRIG --> AND_TRIG{{"AND"}}
AND_TRIG --> GOAL_BLOCK(["[GOAL] block_generation_grupo"])
AND_TRIG --> GOAL_BCAST_DL(["[GOAL] broadcast_active_deadline"])
AND_TRIG --> GOAL_WAIT_DL(["[GOAL] esperar_duracion_deadline"])

GOAL_PUBLISH --> AND_PUB{{"AND"}}
AND_PUB --> GOAL_LIST_STORED(["[GOAL] list_stored_al_supervisor"])
AND_PUB --> GOAL_LIST_UNST(["[GOAL] publicar_unstorable_del_grupo"])
AND_PUB --> GOAL_HARVEST(["[GOAL] harvest_pending_announce"])

GOAL_PICK_EX --> GOAL_FILTER_DL(["[GOAL] filtrar_por_active_deadline"])
GOAL_PICK_EX --> GOAL_PICK_CLOSEST(["[GOAL] pick_closest_exit"])

GOAL_EXEC_EX --> AND_EX{{"AND"}}
AND_EX --> GOAL_NAV_SRC(["[GOAL] navegar_a_origen_shelf_o_entrada"])
AND_EX --> GOAL_RETR(["[GOAL] retrieve_o_pickup"])
AND_EX --> GOAL_GO_EXIT(["[GOAL] go_to_exit_cell"])
AND_EX --> GOAL_DROP_EXIT(["[GOAL] drop_at_exit"])
AND_EX --> GOAL_EXIT_DONE(["[GOAL] notificar_exit_done"])

GOAL_HELP --> AND_HELP{{"AND"}}
AND_HELP --> GOAL_REQ(["[GOAL] ask_for_help"])
AND_HELP --> GOAL_OFFER(["[GOAL] find_offerable_y_help_offer"])
AND_HELP --> GOAL_PICK_OFF(["[GOAL] pick_closest_offer"])
AND_HELP --> GOAL_TAKE(["[GOAL] help_take_y_delegated_stored"])

%% =====================================================
%%  EVITAR SATURACIÓN (supervisor)
%% =====================================================
GOAL_AVOID --> AND_AV{{"AND"}}
AND_AV --> GOAL_OCCUP(["[GOAL] recompute_shelf_usage"])
AND_AV --> GOAL_CHK_GROUP(["[GOAL] check_group_space_70"])
AND_AV --> GOAL_NOTIFY_NOSP(["[GOAL] notificar_no_space_al_scheduler"])
AND_AV --> GOAL_SNAPSHOT(["[GOAL] periodic_snapshot_a_robots"])
AND_AV --> GOAL_AUDIT(["[GOAL] periodic_deadline_audit"])
AND_AV --> GOAL_MARK_FULL(["[GOAL] mark_full_y_maybe_unmark"])

GOAL_CHK_GROUP --> GOAL_SUM_USE(["[GOAL] sum_group_usage"])
GOAL_AUDIT --> GOAL_AUDIT_W(["[GOAL] audit_windows"])
GOAL_AUDIT --> GOAL_REPORT(["[GOAL] report_deadline_missed"])

%% =====================================================
%%  NAVEGAR (mov.asl)
%% =====================================================
GOAL_NAV --> AND_NAV{{"AND"}}
AND_NAV --> GOAL_CLEAR(["[GOAL] clear_nav_state"])
AND_NAV --> GOAL_NEXT(["[GOAL] next_step_eje_Y_prioritario"])
AND_NAV --> GOAL_VALID(["[GOAL] elegir_movimiento_valido"])
AND_NAV --> GOAL_TRY_MV(["[GOAL] try_move"])
AND_NAV --> GOAL_BLOCK_HND(["[GOAL] handle_block"])
AND_NAV --> GOAL_RESET_V(["[GOAL] maybe_reset_visited"])

GOAL_VALID --> GOAL_FRESH(["[GOAL] try_fresh"])
GOAL_VALID --> GOAL_VIS(["[GOAL] try_visited"])
GOAL_VALID --> GOAL_PREV(["[GOAL] try_prev"])

GOAL_BLOCK_HND --> AND_BL{{"AND"}}
AND_BL --> GOAL_QPRI(["[GOAL] query_priority_askOne"])
AND_BL --> GOAL_DECIDE(["[GOAL] decide_block"])
AND_BL --> GOAL_ESCAPE(["[GOAL] escape_around_lateral"])

GOAL_DECIDE --> GOAL_YIELD(["[GOAL] ceder_paso"])
GOAL_DECIDE --> GOAL_GOAROUND(["[GOAL] rodear_obstaculo"])
GOAL_DECIDE --> GOAL_TIE(["[GOAL] desempate_alfabetico"])

%% =====================================================
%%  TRANSPORT (registro pasivo)
%% =====================================================
GOAL_TRANS --> AND_TR{{"AND"}}
AND_TR --> GOAL_LOAD_S(["[GOAL] registrar_load_start"])
AND_TR --> GOAL_LOAD_C(["[GOAL] registrar_container_shipped"])
AND_TR --> GOAL_LOAD_E(["[GOAL] registrar_load_end"])

%% =====================================================
%%  ESTILOS
%% =====================================================
classDef goal fill:#f8d7da,stroke:#721c24,color:#000
classDef andnode fill:#fff3cd,stroke:#856404,color:#000

class GOAL_MAIN,GOAL_STORE,GOAL_EXIT,GOAL_AVOID,GOAL_NAV,GOAL_TRANS goal
class GOAL_ANNOUNCE,GOAL_DECIDE_MGR,GOAL_ENQUEUE,GOAL_PROCESS,GOAL_CHECK_ACC,GOAL_BCAST_NEW,GOAL_BFS,GOAL_RELOC goal
class GOAL_CAN_MNG,GOAL_FASTER,GOAL_PRIO_URG goal
class GOAL_QUERY_LOC,GOAL_CHOOSE,GOAL_RESERVE,GOAL_GOTO_PKG,GOAL_PICKUP,GOAL_MARK_FR,GOAL_NAV_SHELF,GOAL_DROP,GOAL_UNSTOR goal
class GOAL_FITS,GOAL_LOCAL_USE,GOAL_FILTER,GOAL_BCAST_RES,GOAL_VERIFY_POS,GOAL_COMMIT,GOAL_NOTIFY_GUARD goal
class GOAL_TRIG,GOAL_PUBLISH,GOAL_PICK_EX,GOAL_CLAIM,GOAL_EXEC_EX,GOAL_HELP,GOAL_RESHELF,GOAL_CLOSE goal
class GOAL_BLOCK,GOAL_BCAST_DL,GOAL_WAIT_DL,GOAL_LIST_STORED,GOAL_LIST_UNST,GOAL_HARVEST goal
class GOAL_FILTER_DL,GOAL_PICK_CLOSEST goal
class GOAL_NAV_SRC,GOAL_RETR,GOAL_GO_EXIT,GOAL_DROP_EXIT,GOAL_EXIT_DONE goal
class GOAL_REQ,GOAL_OFFER,GOAL_PICK_OFF,GOAL_TAKE goal
class GOAL_OCCUP,GOAL_CHK_GROUP,GOAL_NOTIFY_NOSP,GOAL_SNAPSHOT,GOAL_AUDIT,GOAL_MARK_FULL goal
class GOAL_SUM_USE,GOAL_AUDIT_W,GOAL_REPORT goal
class GOAL_CLEAR,GOAL_NEXT,GOAL_VALID,GOAL_TRY_MV,GOAL_BLOCK_HND,GOAL_RESET_V goal
class GOAL_FRESH,GOAL_VIS,GOAL_PREV goal
class GOAL_QPRI,GOAL_DECIDE,GOAL_ESCAPE goal
class GOAL_YIELD,GOAL_GOAROUND,GOAL_TIE goal
class GOAL_LOAD_S,GOAL_LOAD_C,GOAL_LOAD_E goal
class AND_ROOT,AND_STORE,AND_ANN,AND_PROC,AND_CH,AND_EXIT,AND_TRIG,AND_PUB,AND_EX,AND_HELP,AND_AV,AND_NAV,AND_BL,AND_TR andnode
