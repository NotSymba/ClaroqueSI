flowchart TB
    AG_SCHED["[AG] scheduler"] -- inicia --> INT_NEW{{"[INT] container_available<br>(broadcast nuevo contenedor)"}} & INT_BLOCK{{"[INT] block_generation /<br>unblock_generation"}} & INT_EXIT{{"[INT] exit_item<br>(publicar items a retirar)"}}
    INT_NEW --> ROLE_WORKER["[ROLE] Worker<br>(robot_light, robot_medium,<br>robot_heavy, robot_heavy2)"] & GOAL_STORE(["GOAL Almacenar Contenedores Entrantes"])
    ROLE_WORKER -- internamente --> INT_HEAVY{{"[INT] decide_heavy_peer<br>(arbitraje heavy ↔ heavy2)"}}
    ROLE_WORKER -- inicia --> INT_RES{{"[INT] shelf_reserve / shelf_commit /<br>shelf_release / shelf_retrieved<br>(reserva peer-to-peer)"}} & INT_CLAIM{{"[INT] claim_exit<br>(lock atómico de retirada)"}} & INT_HELP{{"[INT] help_request /<br>help_offer<br>(ayuda peer al más pesado)"}} & INT_PRIO{{"[INT] resolución por prioridad<br>(paso en pasillos)"}}
    INT_RES --> ROLE_WORKER & GOAL_STORE
    ROLE_WORKER -- si no cabe --> INT_UNST{{"[INT] unstorable<br>(no cabe el contenedor)"}}
    INT_UNST --> AG_SCHED
    AG_SUP["[AG] supervisor"] -- inicia --> INT_NOSPACE{{"[INT] no_space(Type)<br>(saturación 70%)"}}
    INT_NOSPACE --> AG_SCHED & GOAL_AVOID(["GOAL Evitar Saturación de Shelves"])
    INT_BLOCK --> ROLE_WORKER
    INT_EXIT --> ROLE_WORKER & GOAL_EXIT(["GOAL Liberar Espacio por Deadline"])
    INT_CLAIM --> AG_SCHED & GOAL_EXIT
    AG_SCHED -- coordina --> AG_TRANS["[AG] transport"]
    AG_TRANS -- inicia --> INT_TRUCK{{"[INT] truck_arrived /<br>retire (camión recoge)"}}
    INT_TRUCK --> AG_SCHED & GOAL_EXIT
    INT_HELP --> ROLE_WORKER & GOAL_NAV(["GOAL Navegar sin Colisiones"])
    INT_PRIO --> ROLE_WORKER & GOAL_NAV
    AG_SUP -. monitoriza .-> ROLE_WORKER & AG_SCHED
    GOAL_STORE --> GOAL_MAIN(["GOAL Gestionar Almacén Inteligente"])
    GOAL_EXIT --> GOAL_MAIN
    GOAL_AVOID --> GOAL_MAIN
    GOAL_NAV --> GOAL_MAIN

     GOAL_MAIN:::goal
     GOAL_STORE:::goal
     GOAL_EXIT:::goal
     GOAL_AVOID:::goal
     GOAL_NAV:::goal
     ROLE_WORKER:::role
     AG_SCHED:::agent
     AG_SUP:::agent
     AG_TRANS:::agent
     INT_NEW:::interaction
     INT_RES:::interaction
     INT_HEAVY:::interaction
     INT_UNST:::interaction
     INT_NOSPACE:::interaction
     INT_EXIT:::interaction
     INT_CLAIM:::interaction
     INT_BLOCK:::interaction
     INT_TRUCK:::interaction
     INT_HELP:::interaction
     INT_PRIO:::interaction
    classDef agent fill:#cce5ff,stroke:#004085,color:#000
    classDef role fill:#d4edda,stroke:#155724,color:#000
    classDef interaction fill:#fff3cd,stroke:#856404,color:#000
    classDef goal fill:#f8d7da,stroke:#721c24,color:#000