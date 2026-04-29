// ═════════════════════════════════════════════════════════════
// NAVIGATION.ASL  —  lógica de movimiento unificada
//
// navigate_to(TX, TY)               → llegar exactamente a (TX,TY)
// navigate_to(TX, TY, adjacent(B))  → B=false: exacto | B=true: dist≤1
// navigate_adjacent(TX, TY)         → alias de navigate_to con adjacent(true)
// navigate_to_shelf(Shelf)          → ir junto a un shelf (rectángulo)
// goto_container(CId)               → ir junto a un contenedor con auto-replan
// ═════════════════════════════════════════════════════════════

movimientoTratado(true).

// Lista tabú: posición anterior para evitar backtracking inmediato
prev_pos(-1, -1).

// Contador de bloqueos consecutivos para activar escape perpendicular
block_streak(0).

// Mejor distancia Manhattan al destino vista en el viaje actual.
// Cuando mejora, borramos visited/2 para permitir caminos nuevos.
best_dist(9999).

sign(X, 1)  :- X > 0.
sign(X, -1) :- X < 0.
sign(X, 0)  :- X = 0.


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


// ═════════════════════════════════════════════════════════════
// NAVEGACIÓN PRINCIPAL — flag adjacent(Bool)
//
// adjacent(false) → llegar exactamente a (TX,TY)
// adjacent(true)  → detenerse cuando dist_manhattan ≤ 1
//
// La condición de parada se evalúa AL INICIO de cada iteración,
// así que si el robot queda adyacente durante un escape o rodeo
// lo detecta inmediatamente sin seguir moviéndose.
// ═════════════════════════════════════════════════════════════

// ── Condición de llegada: modo exacto ────────────────────────
+!navigate_to(TX, TY, adjacent(false)) :
    .my_name(Me) & at(Me, TX, TY)
<-
    -+block_streak(0);
    .print("Llegué a destino exacto: ", TX, ",", TY).

// ── Condición de llegada: modo adyacente (dist ≤ 1) ──────────
+!navigate_to(TX, TY, adjacent(true)) :
    .my_name(Me) & at(Me, CX, CY) &
    math.abs(TX - CX) + math.abs(TY - CY) <= 1
<-
    -+block_streak(0);
    .print("Estoy adyacente a destino: ", TX, ",", TY).

// ── Caso general: calcular y ejecutar siguiente paso ─────────
+!navigate_to(TX, TY, Mode) : true
<-
    .my_name(Me);
    see;
    ?at(Me, CX, CY);
    !maybe_reset_visited(TX, TY, CX, CY);
    !next_step(CX, CY, TX, TY, NX, NY);
    !try_move(NX, NY, TX, TY, Mode).

// ── Wrapper de compatibilidad: navigate_to/2 ─────────────────
// Permite que todo el código existente que llame a navigate_to(X,Y)
// siga funcionando sin cambios.
+!navigate_to(TX, TY) <- !navigate_to(TX, TY, adjacent(false)).


// ═════════════════════════════════════════════════════════════
// navigate_adjacent — alias limpio
//
// Ya NO preselecciona candidatos ni ordena celdas al inicio.
// navigate_to con adjacent(true) evalúa la condición de parada
// en cada iteración, así que el robot se detiene en cuanto esté
// a distancia 1 sin importar por qué ruta llegó.
// ═════════════════════════════════════════════════════════════

+!navigate_adjacent(TX, TY) <-
    !clear_nav_state;
    .print("Navegando adyacente a (", TX, ",", TY, ")");
    !navigate_to(TX, TY, adjacent(true)).


// ═════════════════════════════════════════════════════════════
// DECISIÓN: siguiente celda
// ═════════════════════════════════════════════════════════════

+!next_step(CX, CY, TX, TY, NX, NY)
<-
    DX = TX - CX;
    DY = TY - CY;

    // Priorizar eje Y; usar X solo cuando ya estamos alineados en Y.
    // La distribución de shelves (filas horizontales) hace que avanzar
    // primero en vertical evite atravesar pasillos congestionados.
    if (DY == 0) {
        !candidate_moves_x(CX, CY, TX, TY, Moves)
    } else {
        !candidate_moves_y(CX, CY, TX, TY, Moves)
    };

    !choose_valid(Moves, TX, TY, NX, NY).


// ─────────────────────────────────────────────────────────────
// MOVIMIENTOS CANDIDATOS
// ─────────────────────────────────────────────────────────────

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
// VALIDACIÓN: elegir movimiento válido (3 pasadas)
//
// Pasada 1 — no visitado, no prev_pos            (óptimo)
// Pasada 2 — visitado permitido, no prev_pos     (rodeo)
// Pasada 3 — todo permitido incluyendo prev_pos  (último recurso)
//
// Las pasadas 2 y 3 ordenan por cercanía Manhattan al destino
// para no deambular en dirección opuesta.
// ═════════════════════════════════════════════════════════════

+!choose_valid(Moves, TX, TY, NX, NY) <-
    !try_fresh(Moves, TX, TY, NX, NY).

// ── Pasada 1: no visitados, no prev_pos ──────────────────────
+!try_fresh([pos(X,Y)|_], _, _, X, Y) :
    not robot(_, X, Y) & not shelf(X, Y) & not container(_, X, Y) &
    not prev_pos(X, Y) & not visited(X, Y) &
    X >= 0 & X < 20 & Y >= 0 & Y < 15
<- true.
+!try_fresh([_|Rest], TX, TY, NX, NY) <- !try_fresh(Rest, TX, TY, NX, NY).
+!try_fresh([], TX, TY, NX, NY)       <- !try_visited(TX, TY, NX, NY).

// ── Pasada 2: visitados permitidos, no prev_pos ───────────────
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

// ── Pasada 3: todo permitido incluido prev_pos ────────────────
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
// EJECUCIÓN DEL MOVIMIENTO — propaga Mode
// ═════════════════════════════════════════════════════════════

+!try_move(NX, NY, TX, TY, Mode) :
    timePerMove(T)
<-
    // Si llevamos un fragil, el paso es 15% más lento; en otro caso,
    // usamos el timePerMove del robot tal cual. El belief carrying_fragile
    // lo gestiona work.asl en cada pickup/retrieve/drop.
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
        .print("Bloqueado → reintentando...");
        !handle_block(NX, NY, TX, TY, Mode)
    } else {
        -+block_streak(0);
        !navigate_to(TX, TY, Mode)
    }.

// Compatibilidad con llamadas antiguas a try_move/4
+!try_move(NX, NY, TX, TY) <- !try_move(NX, NY, TX, TY, adjacent(false)).

// ── Recuperación defensiva ────────────────────────────────────
// Si step(...) o cualquier sub-meta del cuerpo lanza fallo (env
// devolvió false por out-of-bounds, excepción inesperada, etc.),
// reseteamos el estado de navegación y reintentamos UNA vez. Si
// el segundo intento también muere, propagamos la fallo arriba
// para que los handlers de handle_container/execute_exit limpien.
-!try_move(_, _, TX, TY, Mode) : not retrying_move <-
    .print("AVISO: try_move falló — limpio estado y reintento navigate_to");
    +retrying_move;
    !clear_nav_state;
    .wait(150);
    !navigate_to(TX, TY, Mode);
    -retrying_move.

-!try_move(NX, NY, _, _, _) <-
    -retrying_move;
    .print("AVISO: try_move(", NX, ",", NY, ") falló por segunda vez — propago fallo").


// ═════════════════════════════════════════════════════════════
// GESTIÓN DE BLOQUEOS — propaga Mode
// ═════════════════════════════════════════════════════════════

+!handle_block(NX, NY, TX, TY, Mode) : priority(MyP) & block_streak(BS)
<-
    NBC = BS + 1;
    -+block_streak(NBC);
    see;
    !resolve_block(NX, NY, TX, TY, MyP, NBC, Mode).

// ── Hay robot en la celda bloqueada → comparar prioridades ───
+!resolve_block(NX, NY, TX, TY, MyP, NBC, Mode) : robot(_, NX, NY)
<-
    !get_other_priority(NX, NY, OtherP);
    if (OtherP < MyP) {
        // El otro tiene más prioridad → yo cedo
        .print("Cedo el paso al robot con mayor prioridad");
        -+block_streak(0);
        !escape_move(TX, TY, Mode)
    } else {
        if (OtherP > MyP) {
            // Yo tengo más prioridad → espero; si el otro no cede, escabo
            .wait(200);
            if (NBC >= 3) {
                .print("Otro no cede tras ", NBC, " intentos → escape");
                -+block_streak(0);
                !escape_move(TX, TY, Mode)
            } else {
                !navigate_to(TX, TY, Mode)
            }
        } else {
            // Misma prioridad → backoff aleatorio
            .random(R);
            W = (math.round(R * 300) + 100);
            .wait(W);
            if (NBC >= 3) {
                -+block_streak(0);
                !escape_move(TX, TY, Mode)
            } else {
                !navigate_to(TX, TY, Mode)
            }
        }
    }.

// ── Fallback: no se detecta quién bloquea ────────────────────
+!resolve_block(NX, NY, TX, TY, MyP, NBC, Mode)
<-
    .random(R);
    W = (math.round(R * 300) + 100);
    .wait(W);
    if (NBC >= 3) {
        -+block_streak(0);
        !escape_move(TX, TY, Mode)
    } else {
        !navigate_to(TX, TY, Mode)
    }.

// ── Obtener prioridad del robot en (NX, NY) ───────────────────
// Se infiere del nombre: *light* → 1 | *medium* → 2 | demás → 3
+!get_other_priority(NX, NY, P) : robot(Name, NX, NY)
<-
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

+!get_other_priority(_, _, 99).   // No encontrado → prioridad baja


// ═════════════════════════════════════════════════════════════
// ESCAPE PERPENDICULAR — propaga Mode
// ═════════════════════════════════════════════════════════════

+!escape_move(TX, TY, Mode)
<-
    .my_name(Me);
    see;
    ?at(Me, CX, CY);

    DX = TX - CX;
    DY = TY - CY;

    // Si el bloqueo es principalmente horizontal, escapa en vertical y viceversa
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
    !try_move(NX, NY, TX, TY, Mode).

// Compatibilidad con llamadas antiguas a escape_move/2
+!escape_move(TX, TY) <- !escape_move(TX, TY, adjacent(false)).


// ════════════════════════════════════════════════════════════
// IR A RECOGER UN CONTENEDOR CON AUTO-REPLAN
//
// Si el scheduler reubica el contenedor durante la navegación,
// al llegar el robot verifica la posición actual; si cambió,
// re-navega. La percepción container_relocated es informativa;
// la verificación post-arribo se encarga del reencaminamiento.
// ════════════════════════════════════════════════════════════

+!goto_container(CId) <-
    -container_relocated(CId, _, _);
    get_location(CId);
    ?location(CId, PX, PY);
    .print("Voy a recoger ", CId, " en (", PX, ",", PY, ")");
    !clear_nav_state;
    !navigate_adjacent(PX, PY);
    !verify_container_pos(CId, PX, PY).

// Percepción informativa de reubicación
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
// NAVEGACIÓN A SHELF (vía casillas adyacentes accesibles)
//
// El entorno provee shelf_adjacent(ShelfId, [pos(X1,Y1),...])
// con las casillas no-shelf que bordean el shelf.
// El robot intenta ir a la más cercana; si falla, prueba la
// siguiente. Usa navigate_to exacto (no adjacent) porque las
// celdas candidatas ya son ellas mismas adyacentes al shelf.
// ═════════════════════════════════════════════════════════════

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

// ── Saltar celda ocupada por robot ───────────────────────────
+!try_shelf_candidates(Shelf) :
    shelf_adj_candidates([pos(TX,TY)|Rest]) & robot(_, TX, TY)
<-
    -+shelf_adj_candidates(Rest);
    .print("Casilla (", TX, ",", TY, ") ocupada por robot, saltando...");
    !try_shelf_candidates(Shelf).

// ── Intentar la siguiente candidata ──────────────────────────
+!try_shelf_candidates(Shelf) :
    shelf_adj_candidates([pos(TX,TY)|Rest])
<-
    -+shelf_adj_candidates(Rest);
    .print("Intentando casilla adyacente a ", Shelf, ": (", TX, ",", TY, ")");
    // navigate_to exacto: la celda candidata ya es adyacente al shelf
    !navigate_to(TX, TY, adjacent(false));
    .my_name(Me);
    see;
    ?at(Me, AX, AY);
    if (AX == TX & AY == TY) {
        .print("Llegué junto a ", Shelf, " en (", TX, ",", TY, ")")
    } else {
        .print("No pude llegar a (", TX, ",", TY, "), probando siguiente...");
        !try_shelf_candidates(Shelf)
    }.

// ── Sin candidatos disponibles ───────────────────────────────
+!try_shelf_candidates(Shelf) :
    shelf_adj_candidates([])
<-
    .print("Sin casillas accesibles para ", Shelf);
    .fail.


// ═════════════════════════════════════════════════════════════
// UTILIDADES: ordenar posiciones por distancia Manhattan
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