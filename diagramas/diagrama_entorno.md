
graph LR
    ENV(("Environment<br/>Warehouse"))

    subgraph PERCEPCIONES["Percepciones"]
        P1["[FFACT] new_container"]
        P2["[FFACT] at"]
        P3["[FFACT] shelf"]
        P4["[FFACT] robot"]
        P5["[FFACT] container"]
        P6["[FFACT] picked"]
        P7["[FFACT] container_at"]
        P8["[FFACT] occupied"]
        P9["[FFACT] container_destroyed"]
        P10["[FFACT] container_relocated"]
        P11["[FFACT] container_exited"]
        P12["[FFACT] package_retrieved"]
        P13["[FFACT] shelf_adjacent"]
        P14["[FFACT] container_info"]
        P15["[FFACT] error"]
        P16["[FFACT] total_errors"]
        P17["[FFACT] current_time"]
    end

    subgraph ACCIONES["Acciones Externas"]
        A1["[APP] step()"]
        A2["[APP] pickup()"]
        A3["[APP] drop_at()"]
        A4["[APP] drop_at_exit()"]
        A5["[APP] retrieve()"]
        A6["[APP] get_container_info()"]
        A7["[APP] relocate_container()"]
        A8["[APP] see()"]
        A9["[APP] get_shelf_adjacent()"]
        A10["[APP] block_generation()"]
        A11["[APP] unblock_generation()"]
        A12["[APP] log_event()"]
        A13["[APP] get_time()"]
    end

    P1 --> ENV
    P2 --> ENV
    P3 --> ENV
    P4 --> ENV
    P5 --> ENV
    P6 --> ENV
    P7 --> ENV
    P8 --> ENV
    P9 --> ENV
    P10 --> ENV
    P11 --> ENV
    P12 --> ENV
    P13 --> ENV
    P14 --> ENV
    P15 --> ENV
    P16 --> ENV
    P17 --> ENV

    ENV --> A1
    ENV --> A2
    ENV --> A3
    ENV --> A4
    ENV --> A5
    ENV --> A6
    ENV --> A7
    ENV --> A8
    ENV --> A9
    ENV --> A10
    ENV --> A11
    ENV --> A12
    ENV --> A13

 