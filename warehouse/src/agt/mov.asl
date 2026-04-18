movimientoTratado(true).

// Lista tabú: posición anterior para evitar backtracking inmediato
prev_pos(-1, -1).

// Contador de bloqueos consecutivos para activar escape perpendicular
block_streak(0).

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
    -+block_streak(0).

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
        !next_step(CX, CY, TX, TY, NX, NY);
        !try_move(NX, NY, TX, TY)
    }.

// ─────────────────────────────────────────────────────────────
// NAVEGACIÓN ADYACENTE
// ─────────────────────────────────────────────────────────────

+!navigate_adjacent(TX, TY) :
    .my_name(Me) &
    at(Me, CX, CY) &
    X = CX - TX &
    Y = CY - TY &
    (math.abs(X) + math.abs(Y) <= 1)
<-
    .print("Estoy en posición adyacente a: ", TX, ",", TY).

+!navigate_adjacent(TX, TY) : true
<-
    .my_name(Me);
    see;
    ?at(Me, CX, CY);
    !next_adjacent_step(CX, CY, TX, TY, NX, NY);
    !try_adjacent_move(NX, NY, TX, TY).

// ─────────────────────────────────────────────────────────────
// DECISIÓN NORMAL
// ─────────────────────────────────────────────────────────────

+!next_step(CX, CY, TX, TY, NX, NY)
<-
    DX = TX - CX;
    DY = TY - CY;

    // Priorizar eje Y, solo usar X cuando ya estamos alineados en Y
    if (DY == 0) {
        !candidate_moves_x(CX, CY, TX, TY, Moves)
    } else {
        !candidate_moves_y(CX, CY, TX, TY, Moves)
    };

    !choose_valid(Moves, NX, NY).

// ─────────────────────────────────────────────────────────────
// DECISIÓN ADYACENTE
// ─────────────────────────────────────────────────────────────

+!next_adjacent_step(CX, CY, TX, TY, NX, NY)
<-
    DX = TX - CX;
    DY = TY - CY;

    ?sign(DX, StepX);
    ?sign(DY, StepY);

    if (StepX == 0) {
        Moves = [
            pos(CX, CY + StepY),
            pos(CX - 1, CY),
            pos(CX + 1, CY),
            pos(CX, CY - StepY)
        ]
    } else {
        if (StepY == 0) {
            Moves = [
                pos(CX + StepX, CY),
                pos(CX, CY - 1),
                pos(CX, CY + 1),
                pos(CX - StepX, CY)
            ]
        } else {
            Moves = [
                pos(CX + StepX, CY),
                pos(CX, CY + StepY),
                pos(CX, CY - StepY),
                pos(CX - StepX, CY)
            ]
        }
    };

    !choose_valid_adjacent(Moves, TX, TY, NX, NY).

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

// Elige el mejor movimiento en 3 pasadas con prioridad decreciente
+!choose_valid(Moves, NX, NY) <-
    !try_fresh(Moves, NX, NY).

// PASADA 1: no visitados, no prev_pos
+!try_fresh([pos(X,Y)|_], X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    not prev_pos(X, Y) & not visited(X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15 <- true.
+!try_fresh([_|Rest], NX, NY) <- !try_fresh(Rest, NX, NY).
+!try_fresh([], NX, NY) <- !try_visited(NX, NY).

// PASADA 2: permitir visitados, no prev_pos (usa la lista original)
+!try_visited(NX, NY) :
    .my_name(Me) & at(Me, CX, CY) <-
    !candidate_fallback(CX, CY, NX, NY).

+!candidate_fallback(CX, CY, NX, NY) <-
    Moves = [pos(CX,CY+1), pos(CX+1,CY), pos(CX-1,CY), pos(CX,CY-1)];
    !try_visited_list(Moves, NX, NY).

+!try_visited_list([pos(X,Y)|_], X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    not prev_pos(X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15 <- true.
+!try_visited_list([_|Rest], NX, NY) <- !try_visited_list(Rest, NX, NY).
+!try_visited_list([], NX, NY) <- !try_prev(NX, NY).

// PASADA 3: permitir incluso prev_pos (último recurso)
+!try_prev(NX, NY) :
    .my_name(Me) & at(Me, CX, CY) <-
    Moves = [pos(CX,CY+1), pos(CX+1,CY), pos(CX-1,CY), pos(CX,CY-1)];
    !try_prev_list(Moves, NX, NY).

+!try_prev_list([pos(X,Y)|_], X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15 <- true.
+!try_prev_list([_|Rest], NX, NY) <- !try_prev_list(Rest, NX, NY).
+!try_prev_list([], _, _) <-
    .print("Sin movimientos válidos → fallo");
    .fail.

// ─────────────────────────────────────────────────────────────
// VALIDACIÓN ADYACENTE
// ─────────────────────────────────────────────────────────────

+!choose_valid_adjacent([pos(X,Y)|_], TX, TY, X, Y) :
    not robot(_, X, Y) &
    not shelf(X, Y) &
    not container(_, X, Y) &
    not (X == TX & Y == TY) &
    not prev_pos(X, Y) &
    X >= 0 & X < 20 &
    Y >= 0 & Y < 15
<-
    true.

+!choose_valid_adjacent([_|Rest], TX, TY, NX, NY)
<-
    !choose_valid_adjacent(Rest, TX, TY, NX, NY).

+!choose_valid_adjacent([], _, _, NX, NY) :
    .my_name(Me) & at(Me, NX, NY)
<-
    true.

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
// EJECUCIÓN ADYACENTE
// ─────────────────────────────────────────────────────────────

+!try_adjacent_move(NX, NY, TX, TY) :
    timePerMove(T)
<-
    .wait(T);
    .my_name(Me);
    ?at(Me, CX, CY);
    -+prev_pos(CX, CY);
    step(NX, NY);
    see;
    !verify_move(NX, NY, TX, TY).

+!verify_move(NX, NY, TX, TY)
<-
    .my_name(Me);
    ?at(Me, AX, AY);

    if (AX == NX & AY == NY) {
        -+last_move(pos(NX, NY));
        !navigate_adjacent(TX, TY)
    } else {
        .print("Movimiento NO aplicado → reintento");
        !navigate_adjacent(TX, TY)
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
        !escape_move(TX, TY)
    } else {
        if (OtherP > MyP) {
            // Yo tengo más prioridad → espero breve, el otro debería ceder
            .wait(200);
            !navigate_to(TX, TY)
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

    if (abs(DX) >= abs(DY)) {
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

    !choose_valid(Moves, NX, NY);
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