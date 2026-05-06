# Decisiones tomadas duarante la realizacion del proyecto:

## 1- Scheduler utiliza un bfs basico para saber si los paquetes son accesibles

    si bien el bfs es un algoritmo tremendamente ineficiente en este caso es util itilizarlo
    porque no tendra que explorar por lo general mas de 6 por 6 contenedores.

### 1.1 ¿Cuando funciona?

    Cuando se genera un paquete se comprueba si el lugar en el que se genero es alcanzable
    para eso se exploran todas las casillas alrededor del paquete, hasta en contrar un
    casilla de tipo empty pues una casilla entrance o clasification.
    Esto se hace con todos los paquetes en la entrada pues un paquete generado puede ser 
    accesible pero puede bloquear a otro

 

### 1.2 ¿Como funciona?
    cuando se genera un nuevo paquete el scheduler llama al plan:
    
    !check_all_packages

    en el que por cada paquete llamara al plan !ensure_accessible(CId, X, Y), que primero
    pregunta a !is_accessible(X, Y, R) (un wrapper sobre !bfs) si la casilla del paquete
    tiene salida hacia una empty_exit. Si la respuesta NO es true se invoca
    !relocate_safely(CId): se reúnen todas las celdas de classification_cell que NO esten
    occupied, se filtran con !pick_accessible_candidate (que vuelve a llamar a !is_accessible
    sobre cada candidata) y se elige la primera que sí pase el BFS. Sólo entonces se ejecuta
    la accion del entorno relocate_container(CId, TX, TY).

    El BFS en si esta implementado por los planes !bfs/3 + !filter_passable/3. La frontera
    de exito es cualquier celda empty_exit; ademas, las celdas zone_cell (entrada y
    clasificacion) se consideran transitables solo si no estan occupied — un paquete
    sentado encima bloquea el paso, que es justo lo que queremos detectar.

    Se han creado una accion en el entorno para realizar esto:
    > relocate_container uso: relocate_container(CId, TargetX, TargetY)
    
    Mueve el contenedor identificado por CId a la celda (TargetX, TargetY). El scheduler
    solo la invoca con celdas que ya pasaron BFS, asi que no se vuelve a comprobar
    accesibilidad despues de la reubicacion.
     
    es posible hacer el bfs porque el agente conoce la topologia del almacen (las celdas
    transitables empty_exit/2, zone_cell/2 y classification_cell/2 estan declaradas como
    creencias estaticas en scheduler.asl, replicando lo que el WarehouseModel.initializeGrid
    construye en Java).

#### Esquema de planes implicados

    +new_container(CId)                              [percept del entorno]
       │
       ├── !check_all_packages
       │     └── findall(container_at(Id,X,Y), L)
       │           └── !process_each(L)
       │                 └── (por cada paquete) !ensure_accessible(Id, X, Y)
       │                        ├── !is_accessible(X, Y, R)
       │                        │     └── !bfs([pos(X,Y)], [pos(X,Y)], R)
       │                        │           └── !filter_passable(Vecinos, Visited, NewOnes)
       │                        │                 (recursivo hasta tocar empty_exit ó cola vacía)
       │                        │
       │                        └── (R \== true) → !relocate_safely(CId)
       │                              ├── findall(pos(DX,DY),
       │                              │      classification_cell(DX,DY) & not occupied(DX,DY),
       │                              │      Candidates)
       │                              ├── !pick_accessible_candidate(Candidates, Dest)
       │                              │     └── !is_accessible(...)   [BFS sobre cada candidata]
       │                              └── relocate_container(CId, TX, TY)   [acción del entorno]
       │
       └── get_container_info(CId)                   [continúa el flujo normal de anuncio]


## 2 Reserva de espacio en estanterias: introduccion al concepto de error acumulado

    En el grupo de WhatsApp barajamos que los robots preguntasen al supervisor
    donde guardar cada paquete: el supervisor llevaria el estado real de las
    estanterias y responderia con la shelf adecuada, garantizando consistencia
    a costa de un round-trip por cada contenedor.

### 2.1 Lo que hicimos en su lugar

    Cada robot lleva su propia copia del estado (shelf_usage_local +
    shelf_reservation) y elige shelf localmente, sin preguntar a nadie. Antes
    del pickup hace una pre-reserva y la difunde a los demas robots con
    shelf_reserve(CId, Shelf, W, V); al confirmar el drop_at envia
    shelf_commit, al fallar el drop shelf_release, y al retirar en un ciclo
    de salida shelf_retrieved. De este modo los cuatro robots ven las
    reservas en vuelo del resto sin pasar por el supervisor.

    Si al elegir ninguna shelf admite el paquete (capacidad − uso − reservas
    < tamaño) el robot manda tell unstorable(CId, Type) al scheduler y NO
    recoge el contenedor. Si lo recogio pero el drop_at fisico falla, libera
    la reserva con shelf_release, lleva el paquete a la zona de salida con
    drop_at_exit y dispara force_exit_cycle (ver seccion 3, casos 2 y 3).

### 2.2 ¿Por que aparece error acumulado?

    Esa copia local se va desincronizando con la realidad: los pesos y
    volumenes son doubles (imprecision numerica al sumar/restar), los
    mensajes peer pueden cruzarse con un commit todavia no aplicado, y una
    reserva puede sobrevivir a un drop que fallo en el entorno. El drift es
    pequeño en cada operacion pero se acumula.

    Para corregirlo el supervisor difunde periodicamente
    shelf_usage_snapshot(L) con la foto autoritativa de los DEPOSITOS
    confirmados (no incluye reservas en vuelo). Cada robot reemplaza su
    shelf_usage_local con esa foto y conserva sus shelf_reservation locales.
    Es un correctivo asincrono: minimiza el drift sin bloquear las
    decisiones, pero no lo elimina entre snapshot y snapshot. De ahi el
    nombre "error acumulado", que retomaremos en la seccion 3 al explicar
    los disparos por unstorable y force_exit_cycle como sintomas de ese
    drift residual.

## 3 Disparos de los ciclos de salida:
Hay 3 tipos de disparo que arrancan un ciclo de salida (begin_exit_cycle/1
en el scheduler). Todos terminan llamando al mismo plan, lo que cambia es
el origen del aviso y el grupo (urgent o normal) sobre el que se dispara.

1- Disparo NORMAL — saturacion del 70 %.
   Lo lanza el supervisor cuando, despues de un package_stored, la suma de
   peso o volumen del GRUPO (urgent ó normal = standard+fragile) supera el
   70 % de la capacidad agregada del grupo. El supervisor envia
   tell no_space(Type) al scheduler y este traduce Type → Group via
   type_group/2 antes de llamar a !begin_exit_cycle(Group). Es la via
   prevista por el enunciado y la unica "sana" — el almacen avisa con
   margen y los robots tienen tiempo de drenar.

2- Disparo por UMBRAL DE UNSTORABLE.
   Cuando un robot recibe un container_available y, tras consultar su
   shelf_usage_local + reservas, comprueba que ninguna estanteria del
   grupo aceptable tiene hueco, envia tell unstorable(CId, Type) al
   scheduler SIN recoger el paquete. El scheduler los acumula por grupo
   y, en cuanto la cuenta de un grupo llega a unstorable_threshold(3),
   arranca el ciclo del grupo afectado.

3- Disparo FORZADO desde robot (force_exit_cycle).
   Caso limite descrito en la seccion 8.1: un robot que YA recogio el
   paquete no encuentra estanteria que lo acepte (la reserva no se valido
   en el drop_at fisico). Tras llevarlo a la zona de salida con
   drop_at_exit, envia tell force_exit_cycle(Type) al scheduler para
   vaciar el grupo y abrir hueco real para los siguientes paquetes.

    Los disparos 2 y 3 son sintomas de errores acumulativos del estado de las
    estanterias (drift de shelf_usage_local respecto a la version del
    supervisor, races con snapshots, imprecision numerica con doubles).
    Evitarlos por completo requeriria un algoritmo de SWAP de contenedores
    entre estanterias del mismo grupo — mover paquetes ya almacenados a otra
    shelf para abrir hueco al que llega — y un protocolo peer-to-peer
    adicional para coordinarlo. No se ha implementado por su complejidad y
    porque, en pruebas, la frecuencia observada es lo bastante baja como para
    que la salida directa + force_exit_cycle sean recuperacion suficiente.

## 4 Robot_*.asl con poco codigo, work.asl con mucho codigo

    Cada robot_*.asl es deliberadamente minimo: declara su identidad
    (idlezone, max_weight, max_size, priority, timePerMove,
    robot_shelf_priority, can_i_manage, faster_capable) y hace include de
    mov.asl + work.asl. El razonamiento (cola, seleccion local de shelf,
    reservas peer, ciclo de salida, navegacion, resolucion de bloqueos) vive
    en esos dos ficheros compartidos.

    De esta manera evitamos repetir codigo entre los cuatro robots y
    dejamos sitio en cada .asl para añadir comportamiento particular cuando
    haga falta. El ejemplo claro es la coordinacion simetrica entre
    robot_heavy y robot_heavy2: ambos llevan is_router_robot, las guardas
    `not is_router_robot` de work.asl evitan que sus planes genericos
    disparen y en su lugar se ejecuta decide_heavy_peer / route_symmetric,
    duplicado intencionalmente entre los dos para que la regla determinista
    (cola → estado → desempate por nombre) sea idéntica en ambos lados.

## 5 ¿Que es nuestro pathfinding?

    Lo que hay en mov.asl es un GREEDY BEST-FIRST SEARCH con heuristica de
    distancia Manhattan, lista de tabú (visited + prev_pos) y resolucion de
    bloqueos peer-to-peer. NO es A*, NO es BFS, NO es Dijkstra: no
    construimos arbol de busqueda ni mantenemos coste acumulado. En cada
    tick el robot mira sus 4 vecinos, los ordena por una preferencia local
    y se mueve a la primera celda valida.

### 5.1 Como elige el siguiente paso

    next_step prioriza el eje Y siempre que haya delta vertical; X solo
    cuando ya estamos alineados en Y. La distribucion horizontal de las
    estanterias hace que el "mayor delta" generico se atasque en pasillos,
    asi que fijamos el orden por construccion.

    La validacion de la celda elegida tiene 3 pasadas en cascada: primero
    try_fresh (no visitada y no prev_pos), si fallan los 4 vecinos pasa a
    try_visited (relaja "no visitado" pero mantiene "no prev_pos") y si
    sigue sin haber, try_prev (relaja todo). Es un tabú con escape
    progresivo. Si se queda sin candidatos en la tercera pasada, falla.

    Cuando el destino es un CONJUNTO de celdas (navigate_to_any para
    shelves, set(Cells) para zonas de entrada/clasificacion) recalculamos
    en cada paso la celda-meta mas cercana, asi que si nos acercamos a otra
    durante el camino, el siguiente next_step ya apunta a esa.

### 5.2 Bloqueos por otro robot

    Si step devuelve blocked_by_agent y hay un robot en la celda destino,
    se le pregunta su prioridad via askOne sobre current_priority/1 (que
    solo unifica si el bloqueador esta moving). Segun la respuesta:
    OtherP < MyP cedo (espero timePerMove y re-navego), OtherP > MyP rodeo
    como obstaculo, empate desempata alfabeticamente por nombre. Si no
    responde o no esta moving se trata como obstaculo estatico y se hace
    escape lateral (un paso perpendicular a la direccion de aproximacion al
    bloqueador).

### 5.3 Por que no es muy bueno

    Greedy best-first NO es completo ni optimo: puede meterse en callejones
    sin salida y depender de las pasadas relajadas para escapar; oscila si
    el destino queda detras de un obstaculo en forma de U; el escape
    lateral solo mira un paso adelante; el reset de tabú al mejorar la
    distancia minima (maybe_reset_visited) es heuristico, no garantia. En
    un grid mas denso o con corredores complejos esto se rompe. Funciona
    aqui porque la topologia es simple, los obstaculos son pocos y las
    pasadas en cascada cubren los casos patologicos. Un A* con replanning
    seria mas robusto, pero el coste de implementarlo y mantenerlo en
    Jason no compensaba para el tamaño del problema.

## 6 Eliminacion de busy en el entorno

    En una version anterior el entorno mantenia booleanos1 por
    robot para evitar que se le asignase trabajo mientras estaba ocupado:
    una herencia de cuando la asignacion se hacia central. Con la
    coordinacion peer-to-peer actual el entorno ya no necesita opinar:
    cada robot lleva su propio state(idle | going_idle | busy) en work.asl
    y son los planes de container_available + decide_heavy_peer los que
    deciden quien encola. Mantener busy en el entorno solo era un recuerdo
    triste de la gestion centralizada y, peor, podia desincronizarse con
    el state interno del robot. Lo quitamos.

## 7 Inevitable algun que otro contenedor aplastado

    Caso: un robot pisa una celda que tiene un contenedor recien generado. Pues cuando usaron see aun no se habia generado, pero cuando se movieron justo se genero.
    (o que el scheduler estaba reubicando) 
    Al pasar esto se llama a escacharPaquete tras el move: El cual se encarga de limpiar las creencias de este contenedor y evitar que el sistema se romà.

    Es una condicion de carrera entre la generacion/reubicacion de
    contenedores y el pathfinding del robot. No la eliminamos del todo:
    requeriria sincronizar el avance de los robots con el spawn del
    entorno, y eso vuelve a centralizar coordinacion en el sitio
    equivocado. Aceptamos el aplastamiento ocasional como coste, contamos
    los destruidos en metricas y notificamos a los agentes con
    container_destroyed para que purguen sus creencias.

## 8 Generacion de contenedores encima de un robot

    El caso simetrico al anterior: el entorno hace pop de un slot libre en
    freeEntranceSlots y genera el contenedor allí, pero ese pool solo
    sigue la pista de los slots SIN paquete — no excluye los slots con un
    robot encima. Si en ese instante un robot esta atravesando una celda
    de entrada, le aparece un contenedor literalmente en la misma celda.
 