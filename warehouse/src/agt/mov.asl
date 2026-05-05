// ═════════════════════════════════════════════════════════════
// MOV.ASL  —  pathfinding greedy con tabú + escape blocker-aware
//
// Exposiciones públicas:
//   navigate_to(TX, TY)               → llegar exactamente a (TX,TY)
//   navigate_to(TX, TY, adjacent(B))  → adjacent(false): exacto
//                                        adjacent(true):  dist Manhattan ≤ 1
//   navigate_adjacent(TX, TY)         → alias con adjacent(true)
//   navigate_to_shelf(Shelf)          → ir junto a una shelf
//   goto_container(CId)               → ir junto a un contenedor con replan
//
// Coordinación de bloqueos (peer-to-peer vía askOne):
//   moving                            → belief activo SOLO durante el viaje
//   current_priority(P) :- moving &
//                          priority(P).
//   Otros robots interrogan esa belief vía
//     .send(Other, askOne, current_priority(_), Reply, Timeout)
//   y obtienen la prioridad real solo si el bloqueador está en marcha.
//   Si no responde (timeout, o no está moviéndose), se trata como
//   obstáculo estático y se escabe alrededor sin esperar.
// ═════════════════════════════════════════════════════════════

movimientoTratado(true).

prev_pos(-1, -1).
block_streak(0).
best_dist(9999).

// Belief consultable por peers: solo unifica si estoy en marcha.
current_priority(P) :- moving & priority(P).

sign(X, 1)  :- X > 0.
sign(X, -1) :- X < 0.
sign(X, 0)  :- X = 0.


// ─────────────────────────────────────────────────────────────
// CICLO DE VIDA DEL VIAJE
// ─────────────────────────────────────────────────────────────

+!clear_nav_state <-
    .abolish(visited(_, _));
    .abolish(last_move(_));
    -+prev_pos(-1, -1);
    -+block_streak(0);
    -+best_dist(9999);
    +moving.

+!end_nav <-
    -moving;
    -+block_streak(0).

// Cuando la distancia Manhattan al destino mejora el mínimo visto,
// borramos la tabla de visitados. Evita quedarse atrapado cuando el
// greedy nos metió en un callejón y ya conseguimos salir.
+!maybe_reset_visited(TX, TY, CX, CY) : best_dist(Best) <-
    D = math.abs(TX - CX) + math.abs(TY - CY);
    if (D < Best) {
        -+best_dist(D);
        .abolish(visited(_, _))
    }.


// ═════════════════════════════════════════════════════════════
// NAVEGACIÓN PRINCIPAL — flag adjacent(Bool)
// ═════════════════════════════════════════════════════════════

// Llegada modo exacto
+!navigate_to(TX, TY, adjacent(false)) :
    .my_name(Me) & at(Me, TX, TY)
<-
    !end_nav;
    .print("Llegué a destino exacto: ", TX, ",", TY).

// Llegada modo adyacente
+!navigate_to(TX, TY, adjacent(true)) :
    .my_name(Me) & at(Me, CX, CY) &
    math.abs(TX - CX) + math.abs(TY - CY) <= 1
<-
    !end_nav;
    .print("Estoy adyacente a destino: ", TX, ",", TY).

// Llegada modo set: estoy ya en una celda del conjunto-meta
+!navigate_to(_, _, set(Cells)) :
    .my_name(Me) & at(Me, CX, CY) & .member(pos(CX, CY), Cells)
<-
    !end_nav;
    .print("Llegué a celda del set en (", CX, ",", CY, ")").

// Caso general modo set: recalcula la celda-meta más cercana en cada paso
+!navigate_to(_, _, set(Cells))
<-
    .my_name(Me);
    see;
    ?at(Me, CX, CY);
    !sort_by_distance(Cells, CX, CY, Sorted);
    [pos(TX, TY) | _] = Sorted;
    !maybe_reset_visited(TX, TY, CX, CY);
    !next_step(CX, CY, TX, TY, NX, NY);
    !try_move(NX, NY, TX, TY, set(Cells)).

// Caso general
+!navigate_to(TX, TY, Mode) : true
<-
    .my_name(Me);
    see;
    ?at(Me, CX, CY);
    !maybe_reset_visited(TX, TY, CX, CY);
    !next_step(CX, CY, TX, TY, NX, NY);
    !try_move(NX, NY, TX, TY, Mode).

// Compat: navigate_to/2 → adjacent(false)
+!navigate_to(TX, TY) <- !navigate_to(TX, TY, adjacent(false)).

+!navigate_adjacent(TX, TY) <-
    !clear_nav_state;
    .print("Navegando adyacente a (", TX, ",", TY, ")");
    !navigate_to(TX, TY, adjacent(true)).

// Navegación a un CONJUNTO de celdas-meta. En cada paso se recalcula
// la más cercana, así que si nos acercamos a otra del set durante el
// viaje, el siguiente paso ya apunta a esa.
+!navigate_to_any(Cells) <-
    !clear_nav_state;
    .print("Navegando a uno de ", Cells, " (target dinámico)");
    !navigate_to(0, 0, set(Cells)).


// ═════════════════════════════════════════════════════════════
// SIGUIENTE CELDA — eje Y prioritario
// ═════════════════════════════════════════════════════════════

+!next_step(CX, CY, TX, TY, NX, NY)
<-
    DY = TY - CY;
    if (DY == 0) {
        !candidate_moves_x(CX, CY, TX, TY, Moves)
    } else {
        !candidate_moves_y(CX, CY, TX, TY, Moves)
    };
    !choose_valid(Moves, TX, TY, NX, NY).

+!candidate_moves_x(CX, CY, TX, TY, Moves)
<-
    if (TX > CX) { StepX = 1  } else { StepX = -1 };
    if (TY > CY) { StepY = 1  } else { StepY = -1 };
    Moves = [
        pos(CX + StepX, CY),
        pos(CX, CY + StepY),
        pos(CX, CY - StepY),
        pos(CX - StepX, CY)
    ].

+!candidate_moves_y(CX, CY, TX, TY, Moves)
<-
    if (TX > CX) { StepX = 1  } else { StepX = -1 };
    if (TY > CY) { StepY = 1  } else { StepY = -1 };
    Moves = [
        pos(CX, CY + StepY),
        pos(CX + StepX, CY),
        pos(CX - StepX, CY),
        pos(CX, CY - StepY)
    ].


// ═════════════════════════════════════════════════════════════
// VALIDACIÓN: 3 pasadas
// ═════════════════════════════════════════════════════════════

+!choose_valid(Moves, TX, TY, NX, NY) <-
    !try_fresh(Moves, TX, TY, NX, NY).

// Pasada 1 — no visitado, no prev_pos
+!try_fresh([pos(X,Y)|_], _, _, X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    not prev_pos(X, Y) & not visited(X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15
<- true.
+!try_fresh([_|Rest], TX, TY, NX, NY) <- !try_fresh(Rest, TX, TY, NX, NY).
+!try_fresh([], TX, TY, NX, NY)       <- !try_visited(TX, TY, NX, NY).

// Pasada 2 — visitados permitidos, no prev_pos
+!try_visited(TX, TY, NX, NY) :
    .my_name(Me) & at(Me, CX, CY)
<-
    AllMoves = [pos(CX,CY+1), pos(CX+1,CY), pos(CX-1,CY), pos(CX,CY-1)];
    !sort_by_distance(AllMoves, TX, TY, Sorted);
    !try_visited_list(Sorted, TX, TY, NX, NY).

+!try_visited_list([pos(X,Y)|_], _, _, X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    not prev_pos(X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15
<- true.
+!try_visited_list([_|Rest], TX, TY, NX, NY) <- !try_visited_list(Rest, TX, TY, NX, NY).
+!try_visited_list([], TX, TY, NX, NY)       <- !try_prev(TX, TY, NX, NY).

// Pasada 3 — todo permitido incluido prev_pos
+!try_prev(TX, TY, NX, NY) :
    .my_name(Me) & at(Me, CX, CY)
<-
    AllMoves = [pos(CX,CY+1), pos(CX+1,CY), pos(CX-1,CY), pos(CX,CY-1)];
    !sort_by_distance(AllMoves, TX, TY, Sorted);
    !try_prev_list(Sorted, NX, NY).

+!try_prev_list([pos(X,Y)|_], X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15
<- true.
+!try_prev_list([_|Rest], NX, NY) <- !try_prev_list(Rest, NX, NY).
+!try_prev_list([], _, _) <-
    .print("Sin movimientos válidos → fallo");
    .fail.


// ═════════════════════════════════════════════════════════════
// EJECUCIÓN DEL MOVIMIENTO
// ═════════════════════════════════════════════════════════════

+!try_move(NX, NY, TX, TY, Mode) :
    timePerMove(T)
<-
    if (carrying_fragile) {
        EffT = math.round(T * 1.15)
    } else {
        EffT = T
    };
    .wait(EffT);
    .my_name(Me);
    ?at(Me, CX, CY);

    -+prev_pos(CX, CY);
    +visited(CX, CY);
    step(NX, NY);
    -+last_move(pos(NX, NY));

    if (error(blocked_by_agent, _)) {
        .print("Bloqueado en (", NX, ",", NY, ") → resolución");
        !handle_block(NX, NY, TX, TY, Mode)
    } else {
        -+block_streak(0);
        !navigate_to(TX, TY, Mode)
    }.

+!try_move(NX, NY, TX, TY) <- !try_move(NX, NY, TX, TY, adjacent(false)).

// Recuperación defensiva: si step falla por motivo distinto al bloqueo
// (oob, excepción), reseteamos estado y reintentamos UNA vez.
-!try_move(_, _, TX, TY, Mode) : not retrying_move <-
    .print("AVISO: try_move falló — limpio estado y reintento navigate_to");
    +retrying_move;
    !clear_nav_state;
    .wait(150);
    !navigate_to(TX, TY, Mode);
    -retrying_move.

-!try_move(NX, NY, _, _, _) <-
    -retrying_move;
    -moving;
    .print("AVISO: try_move(", NX, ",", NY, ") falló por segunda vez — propago fallo").


// ═════════════════════════════════════════════════════════════
// GESTIÓN DE BLOQUEOS — askOne para prioridad real
// ═════════════════════════════════════════════════════════════

+!handle_block(NX, NY, TX, TY, Mode) : priority(MyP) & block_streak(BS)
<-
    NBC = BS + 1;
    -+block_streak(NBC);
    see;
    !resolve_block(NX, NY, TX, TY, MyP, NBC, Mode).

// Bloqueador identificable
+!resolve_block(NX, NY, TX, TY, MyP, NBC, Mode) : robot(Other, NX, NY)
<-
    !query_priority(Other, OtherP);
    !decide_block(Other, NX, NY, TX, TY, MyP, OtherP, NBC, Mode).

// Fallback: percibí blocked_by_agent pero no veo robot en la celda.
// Backoff aleatorio + reintento; si insiste, escape sin coordenadas.
+!resolve_block(NX, NY, TX, TY, _, NBC, Mode)
<-
    .random(R);
    W = math.round(R * 300) + 100;
    .wait(W);
    if (NBC >= 3) {
        -+block_streak(0);
        !escape_around(NX, NY, TX, TY, Mode)
    } else {
        !navigate_to(TX, TY, Mode)
    }.


// ── Decidir según prioridad obtenida ────────────────────────────
//   OtherP = -1   → estático/sin respuesta: escape sin esperar.
//   OtherP < MyP  → más prioridad que yo: cedo, escape alrededor.
//   OtherP > MyP  → menos prioridad: espero; si insiste, escape.
//   OtherP = MyP  → empate: backoff aleatorio; si insiste, escape.

+!decide_block(_, NX, NY, TX, TY, _, -1, _, Mode) <-
    .print("Bloqueador estático/sin respuesta → escape sin esperar");
    -+block_streak(0);
    !escape_around(NX, NY, TX, TY, Mode).

+!decide_block(Other, NX, NY, TX, TY, MyP, OtherP, _, Mode) : OtherP < MyP <-
    .print("Cedo paso a ", Other, " (prioridad ", OtherP, " < mía ", MyP, ")");
    -+block_streak(0);
    !escape_around(NX, NY, TX, TY, Mode).

+!decide_block(Other, NX, NY, TX, TY, MyP, OtherP, NBC, Mode) : OtherP > MyP <-
    .wait(200);
    if (NBC >= 3) {
        .print(Other, " no cede tras ", NBC, " intentos → escape lateral");
        -+block_streak(0);
        !escape_around(NX, NY, TX, TY, Mode)
    } else {
        !navigate_to(TX, TY, Mode)
    }.

+!decide_block(_, NX, NY, TX, TY, _, _, NBC, Mode) <-
    .random(R);
    W = math.round(R * 300) + 100;
    .wait(W);
    if (NBC >= 3) {
        -+block_streak(0);
        !escape_around(NX, NY, TX, TY, Mode)
    } else {
        !navigate_to(TX, TY, Mode)
    }.


// ── Consulta de prioridad por askOne ────────────────────────────
// Si el otro tiene `moving`, su current_priority/1 unifica y devuelve
// el valor real. Si no (idle/parado) o si hay timeout, parse_priority_reply
// devuelve -1 → tratamos como estático.
+!query_priority(Robot, OtherP) <-
    .send(Robot, askOne, current_priority(_), Reply, 200);
    !parse_priority_reply(Reply, OtherP).

+!parse_priority_reply(current_priority(P), P).
+!parse_priority_reply(_, -1).


// ═════════════════════════════════════════════════════════════
// ESCAPE BLOCKER-AWARE
//
// Dado el bloqueador en (BX,BY), el robot da UN paso lateral y deja
// que navigate_to recompute la ruta. Las dos perpendiculares se
// generan rotando 90° la dirección de aproximación (BX-CX, BY-CY).
// El backstep es último recurso.
//
// Las celdas se ordenan por distancia Manhattan al destino, así
// elegimos el lateral que NOS ACERCA al objetivo (no nos lleva a
// sitios raros) entre los que estén libres.
// ═════════════════════════════════════════════════════════════

// Variante set: el "objetivo" para ordenar candidatos de escape se
// recomputa como la celda del set más cercana al bloqueado actual.
+!escape_around(BX, BY, _, _, set(Cells)) :
    .my_name(Me) & at(Me, CX, CY)
<-
    !sort_by_distance(Cells, CX, CY, GoalSorted);
    [pos(TX, TY) | _] = GoalSorted;
    DX = BX - CX;
    DY = BY - CY;
    P1X = CX - DY; P1Y = CY + DX;
    P2X = CX + DY; P2Y = CY - DX;
    BKX = CX - DX; BKY = CY - DY;
    Cand = [pos(P1X, P1Y), pos(P2X, P2Y), pos(BKX, BKY)];
    !sort_by_distance(Cand, TX, TY, Sorted);
    !pick_escape_cell(Sorted, EX, EY);
    .print("Escape lateral set (", EX, ",", EY, ") rodeando bloqueador en (", BX, ",", BY, ")");
    !try_move(EX, EY, TX, TY, set(Cells)).

+!escape_around(BX, BY, TX, TY, Mode) :
    .my_name(Me) & at(Me, CX, CY)
<-
    DX = BX - CX;
    DY = BY - CY;

    // Rotaciones 90° de (DX,DY): (-DY,DX) y (DY,-DX).
    P1X = CX - DY; P1Y = CY + DX;
    P2X = CX + DY; P2Y = CY - DX;
    // Backstep
    BKX = CX - DX; BKY = CY - DY;

    Cand = [pos(P1X, P1Y), pos(P2X, P2Y), pos(BKX, BKY)];
    !sort_by_distance(Cand, TX, TY, Sorted);
    !pick_escape_cell(Sorted, EX, EY);
    .print("Escape lateral (", EX, ",", EY, ") rodeando bloqueador en (", BX, ",", BY, ")");
    !try_move(EX, EY, TX, TY, Mode).

+!pick_escape_cell([pos(X,Y)|_], X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15
<- true.
+!pick_escape_cell([_|Rest], EX, EY) <-
    !pick_escape_cell(Rest, EX, EY).
+!pick_escape_cell([], _, _) <-
    .print("Sin celda de escape libre — propago fallo");
    .fail.


// ═════════════════════════════════════════════════════════════
// IR A RECOGER UN CONTENEDOR CON AUTO-REPLAN
// ═════════════════════════════════════════════════════════════

+!goto_container(CId) <-
    -container_relocated(CId, _, _);
    get_location(CId);
    ?location(CId, PX, PY);
    .print("Voy a recoger ", CId, " en (", PX, ",", PY, ")");
    !clear_nav_state;
    !navigate_adjacent(PX, PY);
    !verify_container_pos(CId, PX, PY).

+container_relocated(CId, NX, NY) <-
    .print("Aviso: ", CId, " reubicado a (", NX, ",", NY, ")").

+!verify_container_pos(CId, PX, PY) <-
    -location(CId, _, _);
    get_location(CId);
    ?location(CId, NPX, NPY);
    if (NPX == PX & NPY == PY) {
        .print("Contenedor ", CId, " confirmado en (", PX, ",", PY, ")")
    } else {
        .print("Contenedor ", CId, " reubicado a (", NPX, ",", NPY, "). Re-navegando...");
        -container_relocated(CId, _, _);
        !clear_nav_state;
        !navigate_adjacent(NPX, NPY);
        !verify_container_pos(CId, NPX, NPY)
    }.


// ═════════════════════════════════════════════════════════════
// NAVEGACIÓN A SHELF (target dinámico entre celdas adyacentes)
// ═════════════════════════════════════════════════════════════

+!navigate_to_shelf(Shelf) <-
    get_shelf_adjacent(Shelf);
    ?shelf_adjacent(Shelf, Cells);
    .print("Navegando a ", Shelf, " (target dinámico entre ", Cells, ")");
    !navigate_to_any(Cells).


// ═════════════════════════════════════════════════════════════
// UTILIDADES — ordenar posiciones por distancia Manhattan
// ═════════════════════════════════════════════════════════════

+!sort_by_distance([], _, _, []).

+!sort_by_distance(Cells, CX, CY, Sorted) <-
    !find_closest(Cells, CX, CY, 9999, pos(-1,-1), Best);
    .delete(Best, Cells, Rest);
    !sort_by_distance(Rest, CX, CY, SortedRest);
    Sorted = [Best | SortedRest].

+!find_closest([], _, _, _, Best, Best).

+!find_closest([pos(X,Y)|Rest], CX, CY, MinD, CurBest, Best) <-
    D = math.abs(X - CX) + math.abs(Y - CY);
    if (D < MinD) {
        !find_closest(Rest, CX, CY, D, pos(X,Y), Best)
    } else {
        !find_closest(Rest, CX, CY, MinD, CurBest, Best)
    }.
