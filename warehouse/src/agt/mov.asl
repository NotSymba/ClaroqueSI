movimientoTratado(true).

// Lista tabú: posición anterior para evitar backtracking inmediato
prev_pos(-1, -1).

// Contador de bloqueos consecutivos para activar escape perpendicular
block_streak(0).

// Mejor distancia Manhattan al destino vista en el viaje actual.
// Cuando mejora, borramos visited/2 para permitir caminos nuevos.
best_dist(9999).

sign(X, 1) :- X > 0.
sign(X, -1) :- X < 0.
sign(X, 0).


// ─────────────────────────────────────────────────────────────
// LIMPIAR ESTADO DE NAVEGACIÓN entre viajes
// ─────────────────────────────────────────────────────────────
+!clear_nav_state <-
    .abolish(visited(_, _));
    .abolish(last_move(_));
    -+prev_pos(-1, -1);
    -+block_streak(0);
    -+best_dist(9999).

// Cuando la distancia Manhattan al destino mejora el mínimo visto,
// borramos la tabla de visitados. Evita quedarse atrapado cuando el
// greedy nos metió en un callejón y ya conseguimos salir.
+!maybe_reset_visited(TX, TY, CX, CY) : best_dist(Best) <-
    D = math.abs(TX - CX) + math.abs(TY - CY);
    if (D < Best) {
        -+best_dist(D);
        .abolish(visited(_, _))
    }.

// ─────────────────────────────────────────────────────────────
// NAVEGACIÓN NORMAL
// ─────────────────────────────────────────────────────────────

+!navigate_to(TX, TY) :
    .my_name(Me) & last_move(pos(TX, TY))
<-
    -+block_streak(0);
    .print("Llegué a destino: ", TX, ",", TY).

+!navigate_to(TX, TY) : true
<-
    .my_name(Me);
    see;
    ?at(Me, CX, CY);
    // Si estamos en el destino (sin last_move previo)
    if (CX == TX & CY == TY) {
        .print("Llegué a destino: ", TX, ",", TY)
    } else {
        !maybe_reset_visited(TX, TY, CX, CY);
        !next_step(CX, CY, TX, TY, NX, NY);
        !try_move(NX, NY, TX, TY)
    }.

// ─────────────────────────────────────────────────────────────
// NAVEGACIÓN ADYACENTE
//
// Reutiliza navigate_to (con escape_move/handle_block/visited reset)
// para ir a una de las 4 celdas adyacentes al objetivo. Si la primera
// candidata no es alcanzable (shelf, fuera del grid, bloqueada de forma
// persistente), prueba la siguiente en orden de cercanía.
// ─────────────────────────────────────────────────────────────

adjacent_candidates([]).

+!navigate_adjacent(TX, TY) :
    .my_name(Me) &
    at(Me, CX, CY) &
    X = CX - TX &
    Y = CY - TY &
    (math.abs(X) + math.abs(Y) <= 1)
<-
    .print("Estoy en posición adyacente a: ", TX, ",", TY).

+!navigate_adjacent(TX, TY) : true <-
    .my_name(Me);
    see;
    ?at(Me, CX, CY);
    Raw = [pos(TX, TY-1), pos(TX, TY+1), pos(TX-1, TY), pos(TX+1, TY)];
    !filter_in_bounds(Raw, Bounded);
    !sort_by_distance(Bounded, CX, CY, Sorted);
    -+adjacent_candidates(Sorted);
    !try_adjacent_candidates(TX, TY).

// ── Filtrar celdas fuera del grid 20x15 ──────────────────────
+!filter_in_bounds([], []).
+!filter_in_bounds([pos(X,Y)|Rest], Out) :
    X >= 0 & X < 20 & Y >= 0 & Y < 15
<-
    !filter_in_bounds(Rest, RestOut);
    Out = [pos(X,Y) | RestOut].
+!filter_in_bounds([_|Rest], Out) <-
    !filter_in_bounds(Rest, Out).

// ── Probar candidatos en orden ───────────────────────────────
// Si la celda está ocupada por un robot ahora mismo, saltarla
// (intentaremos otra y, si todas fallan, volveremos a empezar).
+!try_adjacent_candidates(TX, TY) :
    adjacent_candidates([pos(AX,AY)|Rest]) & robot(_, AX, AY)
<-
    -+adjacent_candidates(Rest);
    .print("Adyacente (", AX, ",", AY, ") ocupada por robot, salto");
    !try_adjacent_candidates(TX, TY).

+!try_adjacent_candidates(TX, TY) :
    adjacent_candidates([pos(AX,AY)|Rest])
<-
    -+adjacent_candidates(Rest);
    .print("Voy a celda adyacente (", AX, ",", AY, ") de (", TX, ",", TY, ")");
    !clear_nav_state;
    !safe_nav_adjacent(AX, AY, TX, TY).

+!try_adjacent_candidates(_, _) :
    adjacent_candidates([])
<-
    .print("Sin celdas adyacentes accesibles");
    .fail.

// Wrapper: si navigate_to(AX,AY) falla con .fail (sin movimientos
// válidos), el handler -!safe_nav_adjacent salta a la siguiente
// candidata en lugar de propagar el fallo al plan padre.
+!safe_nav_adjacent(AX, AY, TX, TY) <-
    !navigate_to(AX, AY);
    .my_name(Me);
    see;
    ?at(Me, CX, CY);
    if (CX == AX & CY == AY) {
        .print("Llegué adyacente a (", TX, ",", TY, ")")
    } else {
        .print("No llegué a (", AX, ",", AY, "), pruebo siguiente");
        !try_adjacent_candidates(TX, TY)
    }.

-!safe_nav_adjacent(AX, AY, TX, TY) <-
    .print("navigate_to(", AX, ",", AY, ") falló, probando siguiente candidata");
    !try_adjacent_candidates(TX, TY).

// ─────────────────────────────────────────────────────────────
// DECISIÓN NORMAL
// ─────────────────────────────────────────────────────────────

+!next_step(CX, CY, TX, TY, NX, NY)
<-
    DX = TX - CX;
    DY = TY - CY;

    // Priorizar eje Y, solo usar X cuando ya estamos alineados en Y.
    // La distribución de shelves (filas horizontales) hace que avanzar
    // primero en vertical evite atravesar pasillos congestionados.
    if (DY == 0) {
        !candidate_moves_x(CX, CY, TX, TY, Moves)
    } else {
        !candidate_moves_y(CX, CY, TX, TY, Moves)
    };

    !choose_valid(Moves, TX, TY, NX, NY).

// ─────────────────────────────────────────────────────────────
// MOVIMIENTOS NORMALES
// ─────────────────────────────────────────────────────────────

+!candidate_moves_x(CX, CY, TX, TY, Moves)
<-
    if (TX > CX) {
        StepX = 1
    } else {
        StepX = -1
    };

    if (TY > CY) {
        StepY = 1
    } else {
        StepY = -1
    };

    Moves = [
        pos(CX + StepX, CY),
        pos(CX, CY + StepY),
        pos(CX, CY - StepY),
        pos(CX - StepX, CY)
    ].

+!candidate_moves_y(CX, CY, TX, TY, Moves)
<-
    if (TX > CX) {
        StepX = 1
    } else {
        StepX = -1
    };

    if (TY > CY) {
        StepY = 1
    } else {
        StepY = -1
    };

    Moves = [
        pos(CX, CY + StepY),
        pos(CX + StepX, CY),
        pos(CX - StepX, CY),
        pos(CX, CY - StepY)
    ].
// ─────────────────────────────────────────────────────────────
// VALIDACIÓN NORMAL (ANTI-BUCLES REAL)
// ─────────────────────────────────────────────────────────────

// Elige el mejor movimiento en 3 pasadas con prioridad decreciente.
// TX,TY se usan en los fallbacks para ordenar candidatos por
// distancia Manhattan al destino (en lugar del orden fijo N,E,O,S
// que ignoraba la dirección y producía caminos largos).
+!choose_valid(Moves, TX, TY, NX, NY) <-
    !try_fresh(Moves, TX, TY, NX, NY).

// PASADA 1: no visitados, no prev_pos
+!try_fresh([pos(X,Y)|_], _, _, X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    not prev_pos(X, Y) & not visited(X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15 <- true.
+!try_fresh([_|Rest], TX, TY, NX, NY) <- !try_fresh(Rest, TX, TY, NX, NY).
+!try_fresh([], TX, TY, NX, NY) <- !try_visited(TX, TY, NX, NY).

// PASADA 2: permitir visitados, no prev_pos.
// Las 4 vecinas se ordenan por distancia Manhattan al destino.
+!try_visited(TX, TY, NX, NY) :
    .my_name(Me) & at(Me, CX, CY) <-
    AllMoves = [pos(CX,CY+1), pos(CX+1,CY), pos(CX-1,CY), pos(CX,CY-1)];
    !sort_by_distance(AllMoves, TX, TY, Sorted);
    !try_visited_list(Sorted, TX, TY, NX, NY).

+!try_visited_list([pos(X,Y)|_], _, _, X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    not prev_pos(X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15 <- true.
+!try_visited_list([_|Rest], TX, TY, NX, NY) <- !try_visited_list(Rest, TX, TY, NX, NY).
+!try_visited_list([], TX, TY, NX, NY) <- !try_prev(TX, TY, NX, NY).

// PASADA 3: permitir incluso prev_pos (último recurso),
// también ordenado por cercanía al destino.
+!try_prev(TX, TY, NX, NY) :
    .my_name(Me) & at(Me, CX, CY) <-
    AllMoves = [pos(CX,CY+1), pos(CX+1,CY), pos(CX-1,CY), pos(CX,CY-1)];
    !sort_by_distance(AllMoves, TX, TY, Sorted);
    !try_prev_list(Sorted, NX, NY).

+!try_prev_list([pos(X,Y)|_], X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15 <- true.
+!try_prev_list([_|Rest], NX, NY) <- !try_prev_list(Rest, NX, NY).
+!try_prev_list([], _, _) <-
    .print("Sin movimientos válidos → fallo");
    .fail.

// ─────────────────────────────────────────────────────────────
// EJECUCIÓN NORMAL
// ─────────────────────────────────────────────────────────────

+!try_move(NX, NY, TX, TY) :
    timePerMove(T)
<-
    .wait(T);
    .my_name(Me);
    ?at(Me, CX, CY);

    -+prev_pos(CX, CY);
    +visited(CX, CY);   //  
    step(NX, NY);
    -+last_move(pos(NX, NY));

    if (error(blocked_by_agent, _)) {
        .print("Bloqueado → reintentando...");
        !handle_block(NX, NY, TX, TY)
    } else {
        -+block_streak(0);
        !navigate_to(TX, TY)
    }.

// ─────────────────────────────────────────────────────────────
// BLOQUEO / BACKOFF CON PRIORIDAD
// El robot de menor prioridad (número mayor) cede el paso.
// ─────────────────────────────────────────────────────────────

+!handle_block(NX, NY, TX, TY) : priority(MyP) & block_streak(BS)
<-
    NBC = BS + 1;
    -+block_streak(NBC);
    see;
    !resolve_block(NX, NY, TX, TY, MyP, NBC).

// Hay un robot en la celda bloqueada → comparar prioridades
+!resolve_block(NX, NY, TX, TY, MyP, NBC) : robot(_, NX, NY) <-
    !get_other_priority(NX, NY, OtherP);
    if (OtherP < MyP) {
        // El otro tiene más prioridad → yo cedo inmediatamente
        .print("Cedo el paso al robot con mayor prioridad");
        -+block_streak(0);
        !escape_move(TX, TY)
    } else {
        if (OtherP > MyP) {
            // Yo tengo más prioridad → espero breve, el otro debería ceder.
            // Si tras varios reintentos el otro sigue parado (p.ej. cargando
            // o esperando), forzamos escape para no quedarnos atrapados.
            .wait(200);
            if (NBC >= 3) {
                .print("Otro no cede tras ", NBC, " intentos → escape");
                -+block_streak(0);
                !escape_move(TX, TY)
            } else {
                !navigate_to(TX, TY)
            }
        } else {
            // Misma prioridad → backoff aleatorio
            .random(R);
            W = (math.round(R * 300) + 100);
            .wait(W);
            if (NBC >= 3) {
                -+block_streak(0);
                !escape_move(TX, TY)
            } else {
                !navigate_to(TX, TY)
            }
        }
    }.

// Caso fallback: no se detecta quién bloquea → backoff clásico
+!resolve_block(NX, NY, TX, TY, MyP, NBC)
<-
    .random(R);
    W = (math.round(R * 300) + 100);
    .wait(W);
    if (NBC >= 3) {
        -+block_streak(0);
        !escape_move(TX, TY)
    } else {
        !navigate_to(TX, TY)
    }.

// Obtener prioridad del robot en la celda (NX, NY)
// Se infiere del nombre: robot_light → 1, robot_medium → 2, robot_heavy → 3
+!get_other_priority(NX, NY, P) : robot(Name, NX, NY) <-
    .term2string(Name, SName);
    if (.substring("light", SName)) {
        P = 1
    } else {
        if (.substring("medium", SName)) {
            P = 2
        } else {
            P = 3
        }
    }.

+!get_other_priority(_, _, 99).  // No se encontró → prioridad baja

// ─────────────────────────────────────────────────────────────
// ESCAPE PERPENDICULAR
// ─────────────────────────────────────────────────────────────

+!escape_move(TX, TY)
<-
    .my_name(Me);
    see;
    ?at(Me, CX, CY);

    DX = TX - CX;
    DY = TY - CY;

    if (math.abs(DX) >= math.abs(DY)) {
        Moves = [
            pos(CX, CY + 1),
            pos(CX, CY - 1),
            pos(CX + 1, CY),
            pos(CX - 1, CY)
        ]
    } else {
        Moves = [
            pos(CX + 1, CY),
            pos(CX - 1, CY),
            pos(CX, CY + 1),
            pos(CX, CY - 1)
        ]
    };

    !choose_valid(Moves, TX, TY, NX, NY);
    !try_move(NX, NY, TX, TY).

// ─────────────────────────────────────────────────────────────
// IR A RECOGER UN CONTENEDOR CON AUTO-REPLAN
//
// Si el scheduler reubica el contenedor durante la navegación, al llegar
// el robot verifica la posición actual; si cambió, re-navega. Si además
// llega el percepto container_relocated(CId,_,_) durante el trayecto,
// aborta navigate_adjacent y re-intenta con la posición actualizada.
// ─────────────────────────────────────────────────────────────

+!goto_container(CId) <-
    -container_relocated(CId, _, _);
    get_location(CId);
    ?location(CId, PX, PY);
    .print("Voy a recoger ", CId, " en (", PX, ",", PY, ")");
    !clear_nav_state;
    !navigate_adjacent(PX, PY);
    !verify_container_pos(CId, PX, PY).

// Percepción informativa — la verificación post-arrive de
// !verify_container_pos se encarga de reencaminar sin abortar intenciones.
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

// ─────────────────────────────────────────────────────────────
// NAVEGACIÓN A SHELF (via casillas adyacentes accesibles)
//
// El entorno provee shelf_adjacent(ShelfId, [pos(X1,Y1),...])
// con las casillas no-shelf que bordean el shelf.
// El robot intenta ir a la más cercana; si falla, prueba la siguiente.
// ─────────────────────────────────────────────────────────────

shelf_adj_candidates([]).

+!navigate_to_shelf(Shelf) <-
    !clear_nav_state;
    get_shelf_adjacent(Shelf);
    .my_name(Me);
    see;
    ?at(Me, CX, CY);
    ?shelf_adjacent(Shelf, AllCells);
    !sort_by_distance(AllCells, CX, CY, Sorted);
    -+shelf_adj_candidates(Sorted);
    !try_shelf_candidates(Shelf).

// ─────────────────────────────────────────────
// PROBAR CANDIDATOS EN ORDEN DE CERCANÍA
// ─────────────────────────────────────────────
// Si hay robot en la casilla candidata, saltarla directamente
+!try_shelf_candidates(Shelf) :
    shelf_adj_candidates([pos(TX,TY)|Rest]) & robot(_, TX, TY) <-
    -+shelf_adj_candidates(Rest);
    .print("Casilla ", TX, ",", TY, " ocupada por robot, saltando...");
    !try_shelf_candidates(Shelf).

+!try_shelf_candidates(Shelf) :
    shelf_adj_candidates([pos(TX,TY)|Rest]) <-
    -+shelf_adj_candidates(Rest);
    .print("Intentando casilla adyacente a ", Shelf, ": ", TX, ",", TY);
    !navigate_to(TX, TY);
    // Verificar si llegamos
    .my_name(Me);
    see;
    ?at(Me, AX, AY);
    if (AX == TX & AY == TY) {
        .print("Llegué junto a ", Shelf, " en (", TX, ",", TY, ")")
    } else {
        .print("No pude llegar a (", TX, ",", TY, "), probando siguiente...");
        !try_shelf_candidates(Shelf)
    }.

+!try_shelf_candidates(Shelf) :
    shelf_adj_candidates([]) <-
    .print("Sin casillas accesibles para ", Shelf);
    .fail.

// ─────────────────────────────────────────────
// ORDENAR LISTA DE POSICIONES POR DISTANCIA MANHATTAN
// ─────────────────────────────────────────────
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