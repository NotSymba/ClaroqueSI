// ═════════════════════════════════════════════════════════════
// WORK.ASL  —  lógica común de trabajo para los robots
//
// Contiene el ciclo estándar de un robot trabajador:
//   cola de contenedores → procesar → ir a por el paquete →
//   pedir estantería al scheduler → navegar → depositar →
//   notificar fin de tarea → volver a idle zone si no hay más.
//
// Cada agente concreto (light, medium, heavy, heavy2) incluye
// este fichero y añade únicamente su parte individual: capacidad,
// velocidad, prioridad, can_i_manage y el manejo de container_info
// (routing en el caso de heavy/heavy2).
// ═════════════════════════════════════════════════════════════

state(idle).
container_queue([]).

// ─────────────────────────────────────────────────────────────
//  COLA DE CONTENEDORES
// ─────────────────────────────────────────────────────────────
+!enqueue(CId, W, H, Weight, urgent) : container_queue(Q) <-
    -container_queue(_);
    +container_queue([pkg(CId, Weight, W, H, urgent) | Q]);
    .print("Encolado urgente: ", CId);
    !check_idle.

+!enqueue(CId, W, H, Weight, Type) : container_queue(Q) <-
    .concat(Q, [pkg(CId, Weight, W, H, Type)], NewQ);
    -container_queue(_);
    +container_queue(NewQ);
    .print("Encolado: ", CId);
    !check_idle.

+!check_idle : state(idle) <- !process_next.
+!check_idle : state(going_idle) <-
    .drop_intention(go_idle);
    -+state(idle);
    !process_next.
+!check_idle <- true.

// ─────────────────────────────────────────────────────────────
//  PROCESAR COLA
// ─────────────────────────────────────────────────────────────
+!process_next : container_queue([]) <- !go_idle.

+!process_next :
    container_queue([pkg(CId, Weight, W, H, Type) | Rest]) &
    state(idle) <-
    -+container_queue(Rest);
    -state(idle);
    +state(busy);
    !handle_container(CId, Weight, W, H, Type).

// ─────────────────────────────────────────────────────────────
//  GESTIÓN DE UN CONTENEDOR
//  La estantería la decide el scheduler (consultando al supervisor por
//  la capacidad disponible). El robot solo pregunta y espera respuesta.
// ─────────────────────────────────────────────────────────────
+!handle_container(CId, Weight, W, H, Type) <-
    !goto_container(CId);
    pickup(CId);
    !request_shelf_assignment(CId, Weight, W, H, Type, TargetShelf);
    !navigate_to_shelf(TargetShelf);
    !try_drop(CId, Weight, W, H, Type, TargetShelf);
    !finish_task(CId, TargetShelf).

// ─────────────────────────────────────────────────────────────
//  PEDIR ESTANTERÍA AL SCHEDULER Y ESPERAR RESPUESTA
// ─────────────────────────────────────────────────────────────
+!request_shelf_assignment(CId, Weight, W, H, Type, Shelf) <-
    .my_name(Me);
    see;
    ?at(Me, RX, RY);
    V = W * H;
    .abolish(shelf_assigned(CId, _));
    .send(scheduler, tell, request_shelf(CId, Weight, V, Type, RX, RY));
    .wait({+shelf_assigned(CId, _)}, 30000, _);
    if (shelf_assigned(CId, A)) {
        Answer = A;
        .abolish(shelf_assigned(CId, _));
    } else {
        .print("Timeout esperando shelf_assigned de scheduler para ", CId);
        Answer = none
    };
    if (Answer == none) {
        .print("Sin estantería disponible para ", CId, ", reintentando en 2s...");
        .wait(2000);
        !request_shelf_assignment(CId, Weight, W, H, Type, Shelf)
    } else {
        Shelf = Answer
    }.

// ─────────────────────────────────────────────────────────────
//  DEPOSITAR
//  Si drop_at falla, avisamos al scheduler (que excluirá la estantería)
//  y pedimos otra.
// ─────────────────────────────────────────────────────────────
+!try_drop(CId, Weight, W, H, Type, Shelf) <-
    drop_at(Shelf);
    .print("Depositado ", CId, " en ", Shelf).

-!try_drop(CId, Weight, W, H, Type, Shelf) <-
    .print("Fallo al depositar ", CId, " en ", Shelf, ", pidiendo nueva estantería...");
    .send(scheduler, tell, drop_failed(CId, Shelf));
    !request_shelf_assignment(CId, Weight, W, H, Type, AltShelf);
    !navigate_to_shelf(AltShelf);
    !try_drop(CId, Weight, W, H, Type, AltShelf).

// ─────────────────────────────────────────────────────────────
//  FINALIZAR TAREA → notificar al scheduler vía task_complete
// ─────────────────────────────────────────────────────────────
+!finish_task(CId, Shelf) <-
    task_complete(CId, Shelf);
    .send(scheduler, tell, guardado(CId, Shelf));
    -+state(idle);
    .print("Completado: ", CId, " → ", Shelf);
    !process_next.

// ─────────────────────────────────────────────────────────────
//  IR A IDLE ZONE cuando no hay trabajo
// ─────────────────────────────────────────────────────────────
+!go_idle : idlezone(IX, IY) <-
    -+state(going_idle);
    .print("Sin trabajo, volviendo a idle zone (", IX, ",", IY, ")");
    !clear_nav_state;
    !navigate_to(IX, IY);
    -+state(idle);
    .print("En idle zone, esperando trabajo...").

-!go_idle <-
    .print("No pude llegar a idle zone, esperando trabajo aquí");
    -+state(idle).
