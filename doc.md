# Documentación Técnica — Sistema Multiagente de Almacén Automatizado

> Documento intermedio. Pretende servir de base a una memoria final más
> profesional. Prioridad: explicar cómo se comporta el sistema en
> ejecución y, en particular, cómo funciona el **ciclo de salida**, que
> es la pieza central de esta iteración.

---

## 1. Visión general del proyecto

### 1.1 Qué hace el sistema

El sistema simula un **almacén logístico automatizado** gestionado por
robots autónomos. El flujo, visto desde fuera, es el siguiente:

1. Un **generador externo** (hilo Java) produce contenedores cada
   5–10 s en una zona de entrada. Cada contenedor tiene un peso
   aleatorio, unas dimensiones (1×1, 1×2, 2×2 o 2×3) y un tipo
   (`standard`, `fragile` o `urgent`).
2. Cuatro **robots reponedores** con capacidades distintas (light,
   medium, heavy, heavy2) los recogen, eligen una **estantería**
   compatible y los almacenan.
3. Cuando una estantería del grupo se llena por encima del **70 %**,
   o se acumulan demasiados paquetes que ningún robot pudo
   almacenar, se dispara un **ciclo de salida**: durante una
   ventana temporal acotada los robots dejan de almacenar y se
   dedican a sacar los paquetes del grupo afectado por la **zona
   de salida**, donde un agente `transport` simulado los recoge.
4. Un agente `supervisor` lleva la contabilidad real (ocupación de
   estanterías, paquetes recibidos vs. almacenados, errores) y es
   quien dispara el aviso de saturación al scheduler.

### 1.2 Arquitectura general

El sistema combina dos capas claramente separadas:

```
┌────────────────────────────────────────────────────────────────┐
│                CAPA DE AGENTES JASON (BDI, .asl)               │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐       │
│  │ robot_* │  │ scheduler│  │supervisor│  │ transport  │       │
│  └────┬────┘  └────┬─────┘  └────┬─────┘  └─────┬──────┘       │
│       │            │             │               │              │
│       │  mensajes (.send, .broadcast) + percepts (env)          │
└───────┼────────────┼─────────────┼───────────────┼──────────────┘
        ▼            ▼             ▼               ▼
┌────────────────────────────────────────────────────────────────┐
│            CAPA DE ENTORNO Y MODELO (Java)                     │
│  WarehouseArtifact (Environment de Jason)                      │
│  WarehouseModel    (estado: grid, contenedores, robots…)       │
│  WarehouseView     (Swing — visualización)                     │
│  Robot · Container · Shelf · CellType · Location · Nodo        │
└────────────────────────────────────────────────────────────────┘
```

**Principio clave**: el entorno solo expone **estado y acciones
"tontas"** (`step`, `pickup`, `drop_at`, `drop_at_exit`, `retrieve`,
`relocate_container`, `see`, `get_container_info`,
`get_shelf_adjacent`, `block_generation`/`unblock_generation`,
`log_event`). Toda la coordinación, prioridades, reservas y
razonamiento vive en los `.asl`. El entorno nunca decide quién hace qué.

### 1.3 Topología fija (memorización útil)

El grid es de **20×15** celdas:

| Zona            | Coordenadas              | Color GUI |
|-----------------|--------------------------|-----------|
| Salida          | `x ∈ [0..2], y ∈ [0..1]` | Azul      |
| Clasificación   | `x ∈ [3..4], y ∈ [0..1]` | Amarillo  |
| Entrada         | `x ∈ [5..7], y ∈ [0..1]` | Verde     |
| Pasillos EMPTY  | `(x,2)` con x∈[3..7], `(8,0)`, `(8,1)` | Blanco |

**Estanterías** (9 en total, multi-celda):

| Shelf      | Origen (x,y) | Tamaño | Cap. peso | Cap. vol | Tipo admitido       |
|------------|--------------|--------|-----------|----------|---------------------|
| shelf_1    | (10, 2)      | 2×2    | 50 kg     | 8 u      | urgent              |
| shelf_2    | (12, 2)      | 2×2    | 50 kg     | 8 u      | standard / fragile  |
| shelf_3    | (14, 2)      | 2×2    | 50 kg     | 8 u      | standard / fragile  |
| shelf_4    | (16, 2)      | 2×2    | 50 kg     | 8 u      | standard / fragile  |
| shelf_5    | (10, 6)      | 3×2    | 100 kg    | 12 u     | urgent              |
| shelf_6    | (13, 6)      | 3×2    | 100 kg    | 12 u     | standard / fragile  |
| shelf_7    | (16, 6)      | 3×2    | 100 kg    | 12 u     | standard / fragile  |
| shelf_8    | (10, 10)     | 4×3    | 200 kg    | 20 u     | urgent              |
| shelf_9    | (14, 10)     | 4×3    | 200 kg    | 20 u     | standard / fragile  |

### 1.4 Agentes y propósito

| Agente        | Tipo           | Propósito                                           |
|---------------|----------------|-----------------------------------------------------|
| `robot_light` | Trabajador     | Paquetes pequeños (≤10 kg, 1×1)                     |
| `robot_medium`| Trabajador     | Paquetes medianos (>10 kg o >1×1, ≤30 kg, ≤1×2)     |
| `robot_heavy` | Trabajador     | Paquetes pesados (>30 kg o >1×2, ≤100 kg, ≤2×3)     |
| `robot_heavy2`| Trabajador     | Idem heavy — coordinado simétricamente con heavy    |
| `scheduler`   | Coordinador    | Punto de información, ciclo de salida, accesibilidad|
| `supervisor`  | Monitor        | Métricas, ocupación real, dispara `no_space`        |
| `transport`   | Externo (sim.) | Camión que "recoge" en cada deadline                |

---

## 2. Documentación detallada de cada agente

Para cada agente: objetivo, responsabilidades, flujo y todos (o
casi todos) los planes que define, agrupados por bloque temático.

---

### 2.1 Agente `scheduler` — coordinador y orquestador

**Objetivo principal**: ser el punto central de información y
disparar el ciclo de salida cuando el supervisor o un robot lo
piden. **No** asigna estanterías a robots ni reparte paquetes
explícitamente: solo anuncia.

#### Responsabilidades

1. **Anunciar nuevos contenedores** a los cuatro robots vía
   `container_available(CId, W, H, Weight, Type)` en cuanto el
   entorno emite `+new_container(CId)`.
2. **Cachear `package_info`** (peso/volumen/tipo) y reenviárselo al
   supervisor (`package_arrived`).
3. **Garantizar accesibilidad**: ante un nuevo contenedor lanza
   un BFS sobre todos los paquetes pendientes; si alguno quedó
   atrapado por otros paquetes, ordena al entorno una
   `relocate_container` a una celda libre de clasificación.
4. **Responder consultas** (`provide_location(CId, Requester)`):
   los robots preguntan la posición actual antes de ir a recoger.
5. **Mantener registros de almacenamiento** (`guardado(CId, Shelf, W, V)`
   reenviado al supervisor como `package_stored`). El robot incluye
   peso y volumen — el scheduler ya no depende de su caché
   `package_info` para informar al supervisor (evita el caso
   degenerado `package_stored(...,0,0,unknown)` cuando hay races
   con `container_exited`/`container_destroyed` previos).
6. **Disparar y orquestar el ciclo de salida** cuando recibe
   `no_space(Type)` del supervisor, `force_exit_cycle(Type)` de un
   robot o cuando se acumulan ≥ `unstorable_threshold` (=3)
   paquetes que ningún robot pudo almacenar en un grupo.
7. **Gestionar la cola de deadlines pendientes** (FIFO con dedup):
   si llega un trigger durante un ciclo activo, se encola y se
   ejecuta en cadena al cerrar el actual sin liberar el lock
   `exit_cycle_active` entre uno y otro.
8. **Limpieza ante destrucción de paquetes** (`container_destroyed`):
   abolir cachés, anuncios pendientes, claims, exit_items y avisar
   a robots vía `untell` para no dejar referencias huérfanas.

#### Topología que el scheduler conoce localmente

Hay **duplicación intencionada** de la topología: el scheduler
tiene `shelf_location/3`, `zone_cell/2`, `classification_cell/2`,
`empty_exit/2` y `exit_cell/2` para no depender del entorno en
cada decisión.

Define `type_group/2` para agrupar tipos en `urgent` y `normal`
(standard + fragile comparten shelves), y la regla derivada
`blocked_type(Type) :- type_group(Type, G) & blocked_group(G)`.

#### Planes principales del scheduler

##### Iniciación y entrada de contenedores

```jason
+!start <- .print("Scheduler online…").

+new_container(CId) <-
    !check_all_packages;
    get_container_info(CId).

+container_info(CId, W, H, Weight, Type) <-
    V = W * H;
    .abolish(package_info(CId, _, _, _));
    +package_info(CId, Weight, V, Type);
    .send(supervisor, tell, package_arrived(CId, Weight, V, Type));
    !announce_if_allowed(CId, W, H, Weight, Type);
    -container_info(CId, W, H, Weight, Type).
```

`announce_if_allowed`:
- Si `blocked_type(Type)` (tipo bloqueado por ciclo activo): se
  guarda como `pending_announce(CId, W, H, Weight, Type)` y se
  publicará al terminar el ciclo (vía `flush_all_pending_announce`).
- Si no, se hace `.send(robot_*, tell, container_available(...))`
  a los cuatro robots.

##### Consulta de ubicación

Los robots, antes de navegar, piden ubicación porque pueden
haberse reubicado:

```jason
+!provide_location(CId, Requester) : container_at(CId, X, Y) <-
    .send(Requester, tell, container_location(CId, X, Y)).
+!provide_location(CId, Requester) <-
    .send(Requester, tell, container_location(CId, none, none)).
```

`container_at/3` lo mantiene el entorno como percept del scheduler.

##### Comprobación de accesibilidad (BFS)

`check_all_packages` itera sobre todos los `container_at(Id,X,Y)`
y para cada uno comprueba `is_accessible/3`. Si no es accesible,
`relocate_safely` busca una celda de clasificación libre y
accesible y emite `relocate_container(CId, TX, TY)`.

`is_accessible` ejecuta un BFS que parte de la celda del paquete
y se expande por celdas pasables (zonas y EMPTY no ocupadas)
hasta encontrar una celda `empty_exit/2` (los pasillos que
conectan con el resto del almacén). Si nunca llega a ninguna,
`R = false` y se reubica.

##### Ciclo de salida — disparadores

Tres formas de arrancar un ciclo:

1. **Supervisor** detecta saturación ≥ 70 % de un grupo:
   `no_space(Type)[source(supervisor)]` → `begin_exit_cycle(Group)`.
2. **Acumulación de unstorable**: cada vez que un robot envía
   `tell unstorable(CId, Type)`, scheduler hace
   `record_unstorable(CId, Group)` y comprueba el umbral
   (`unstorable_threshold(3)`). Al alcanzarlo:
   `begin_exit_cycle(Group)`.
3. **Caso límite — robot fuerza ciclo**: un robot cargado que ya
   no puede colocar el paquete envía
   `tell force_exit_cycle(Type)`; se traduce a
   `begin_exit_cycle(Group)`.

Si ya hay un ciclo activo (`exit_cycle_active`), el trigger se
encola con dedup en `pending_queue`.

##### Cuerpo del ciclo de salida

```jason
+!begin_exit_cycle(TriggerGroup) <-
    +exit_cycle_active;
    !run_one_deadline(TriggerGroup).

+!run_one_deadline(Group) <-
    +trigger_group(Group);
    !block_group(Group);
    .send(supervisor, tell, exit_cycle_started);
    log_event(output_phase_started, Group);
    !run_deadline_for(Group);
    !end_exit_cycle(Group).
```

`run_deadline_for` despacha al deadline correcto:

| Group   | Deadline | Tipos               | Duración           | Shelves          |
|---------|----------|---------------------|--------------------|------------------|
| urgent  | short    | `[urgent]`          | `ΔT  = 30 000 ms`  | 1, 5, 8          |
| normal  | long     | `[standard, fragile]`| `3·ΔT = 90 000 ms` | 2, 3, 4, 6, 7, 9 |

`block_group` llama a la acción del entorno
`block_generation(Type)` por cada tipo del grupo y añade el
hecho `blocked_group(Group)`.

`run_deadline`:

```jason
+!run_deadline(Kind, Types, Factor) :
        delta_t(DT) & trigger_group(Group) <-
    Duration = DT * Factor;
    +active_deadline(Kind);
    +deadline_shipped_count(Kind, 0);
    log_event(deadline_started, Group);
    .send(transport, tell, load_start(Kind, Types));
    .send(supervisor, tell, deadline_started(Kind, Types, Duration));
    !broadcast_deadline_start(Kind);          // .broadcast(tell, active_deadline(Kind))
    !publish_stored_items(Types, Kind);       // pide al supervisor list_stored
    !publish_unstorable_items(Types, Kind);   // los pendientes no almacenables
    .wait(Duration);
    !close_deadline(Kind).
```

`publish_stored_items` pide al supervisor (`achieve list_stored`)
la lista de paquetes almacenados de los tipos del deadline. El
supervisor responde con
`stored_list_response(Kind, [s(CId, Shelf, W, V, Type), ...])`.
Para cada uno, scheduler emite a los **cuatro robots**
`tell exit_item(CId, at_shelf(Shelf), W, V, Type, Kind)`.

`publish_unstorable_items` hace lo análogo con los unstorable:
primero **cosecha** los `pending_announce` del grupo
(`harvest_pending_announce_for_group`) y los reclasifica como
`unstorable_pending`, después publica `exit_item(CId,
at_entry(X,Y), …)` por cada uno.

`close_deadline`:

```jason
+!close_deadline(Kind) : trigger_group(Group) <-
    -active_deadline(Kind);
    ?deadline_shipped_count(Kind, N);
    log_event(deadline_ended, Group);
    .send(transport, tell, load_end(Kind, N));
    !broadcast_deadline_end(Kind);            // .broadcast(untell, active_deadline)
    !abolish_all_exit_items(Kind).            // limpia exit_items no consumidos
```

##### Claim — lock atómico al retirar un paquete

Cuando un robot escoge un `exit_item`, pide permiso:

```jason
+!claim_exit(CId, Requester)[source(Requester)] :
        pending_exit(CId, _, _, _, _, _) & not claimed(CId) <-
    +claimed(CId);
    .send(Requester, tell, claim_result(CId, granted));
    .broadcast(tell, exit_taken(CId)).        // los demás abolishen su copia

+!claim_exit(CId, Requester)[source(Requester)] <-
    .send(Requester, tell, claim_result(CId, denied)).
```

##### Notificación de fin de tarea

Cuando un robot deposita en la zona de salida envía
`tell exit_done(CId, Type)`. El scheduler:

```jason
+exit_done(CId, Type)[source(Reporter)] <-
    .send(transport, tell, container_shipped(CId, Type));
    !remove_from_unstorable(CId);
    !bump_shipped_count;            // incrementa deadline_shipped_count(K, _)
    -pending_exit(CId, _, _, _, _, _);
    -claimed(CId);
    .broadcast(untell, exit_taken(CId)).
```

##### Cierre del ciclo y encadenamiento

```jason
+!end_exit_cycle(TriggerGroup) <-
    -trigger_group(_);
    !unblock_group(TriggerGroup);
    .send(supervisor, tell, exit_cycle_ended(TriggerGroup));
    !flush_all_pending_announce;
    !chain_or_release.

+!chain_or_release : pending_queue([Next | Rest]) <-
    -+pending_queue(Rest);
    !run_one_deadline(Next).        // ¡sin liberar exit_cycle_active!

+!chain_or_release <-
    -exit_cycle_active.
```

La **clave** es que `chain_or_release` decide si encadena o libera:
no se libera el lock entre deadlines encolados, evitando una
carrera en la que un nuevo trigger arrancaría un segundo ciclo en
paralelo.

##### Limpieza por destrucción

```jason
+container_destroyed(CId, Type) <-
    .abolish(package_info(CId, _, _, _));
    .abolish(pending_announce(CId, _, _, _, _));
    .abolish(claimed(CId));
    .abolish(pending_exit(CId, _, _, _, _, _));
    .abolish(container_at(CId, _, _));
    !remove_from_unstorable(CId);
    .broadcast(untell, exit_item(CId, _, _, _, _, _));
    .broadcast(untell, container_available(CId, _, _, _, _));
    .broadcast(untell, exit_taken(CId));
    -container_destroyed(CId, Type).
```

#### Estados implícitos del scheduler

No define un automaton explícito, pero opera en dos modos:

- **Modo normal**: anuncia, responde consultas, registra. No hay
  `exit_cycle_active`.
- **Modo ciclo de salida**: `exit_cycle_active` y
  `trigger_group(_)` activos. Bloquea generación del grupo,
  encola triggers nuevos.

---

### 2.2 Agente `supervisor` — monitor

**Objetivo principal**: mantener la fotografía real del almacén y
detectar cuándo un grupo de tipos llega al **70 % de saturación**
agregada para avisar al scheduler.

#### Responsabilidades

1. **Métricas**: total recibidos, total almacenados, total errores
   por tipo, incumplimientos de deadline.
2. **Ocupación real de cada estantería** (`shelf_usage/3`),
   **derivada** (no acumulativa) de `stored_at`. Tras cada
   `package_stored`/`package_retrieved` se invoca
   `recompute_shelf_usage(Shelf)`, que suma los `(W, V)` de los
   `stored_at(_, Shelf, _, W, V)` vivos y reescribe `shelf_usage`
   limpio. Beneficio: un evento perdido afecta como mucho a un
   contenedor y se corrige al siguiente recompute, **nunca se
   compone** con errores futuros (ya no hay drift acumulativo ni
   posibilidad de valores negativos).
3. **Registro `stored_at(CId, Shelf, Type, W, V)`**: qué paquete
   está en qué estantería. Es la **única fuente de verdad** del
   supervisor: tanto `shelf_usage` como las respuestas al scheduler
   se derivan de aquí. Lo necesita el scheduler para construir la
   lista de exit_items en cada deadline.
4. **Disparar `no_space(Type)`** al scheduler cuando la suma
   peso/volumen de las shelves del grupo supera 70 %, con
   bloqueo `blocked_group_notified(Group)` para no spamear.
5. **Vigilancia temporal de deadlines**: arrancar un timer cuando
   el scheduler le envía `deadline_started(Kind, Types, Duration)`
   y, al expirar, auditar qué `at_warehouse(CId, Type, _, _)` de
   esos tipos sigue en el almacén — cada pendiente cuenta como
   incumplimiento informativo (`deadline_violations` ++) y emite
   `log_event(deadline_missed, CId)`.
6. **`list_stored(Types, Kind)`**: contestar al scheduler con la
   lista de `s(CId, Shelf, W, V, Type)` de los stored_at de esos
   tipos.

#### Planes principales

##### Recepción de paquetes

```jason
+package_arrived(CId, Weight, Volume, Type)[source(scheduler)] <-
    +at_warehouse(CId, Type, Weight, Volume);
    -package_arrived(...).
```

##### Almacenamiento — actualiza ocupación + comprueba umbrales

```jason
@pkg_stored_known[atomic]
+package_stored(CId, Shelf, Weight, Volume, Type)[source(scheduler)] :
        shelf_capacity(Shelf, MaxW, MaxV) & total_stored(N) <-
    +stored_at(CId, Shelf, Type, Weight, Volume);
    !recompute_shelf_usage(Shelf);
    ?shelf_usage(Shelf, NewW, NewV);
    -+total_stored(N + 1);
    !check_shelf_limits(Shelf, NewW, NewV, MaxW, MaxV);
    !check_type_space(Type);
    !broadcast_usage_snapshot;
    !calculate_statistics.
```

`@atomic` evita que dos `package_stored` concurrentes se pisen al
recomputar (la suma sobre `stored_at` y la reescritura de
`shelf_usage` deben verse atómicas). Tras cada actualización el
supervisor emite un snapshot autoritativo (`broadcast_usage_snapshot`)
para que los robots reconcilien `shelf_usage_local`.

`recompute_shelf_usage(Shelf)`:

```jason
+!recompute_shelf_usage(Shelf) <-
    .findall(uw(W, V), stored_at(_, Shelf, _, W, V), L);
    !sum_uw(L, 0, 0, NewW, NewV);
    .abolish(shelf_usage(Shelf, _, _));
    +shelf_usage(Shelf, NewW, NewV).
```

##### Comprobación de saturación por grupo

```jason
+!check_type_space(Type) :
        type_group(Type, Group) & blocked_group_notified(Group) <- true.

+!check_type_space(Type) :
        type_group(Type, Group) & type_full_ratio(R) <-
    !sum_group_usage(Group, UW, UV, MW, MV);
    if (MW > 0 & (UW >= MW * R | UV >= MV * R)) {
        +blocked_group_notified(Group);
        log_event(no_space_detected, Type);
        .send(scheduler, tell, no_space(Type))
    }.
```

`sum_group_usage` agrega peso/volumen actual y máximo de **todas
las shelves que admiten algún tipo del grupo** (con dedup para no
contar shelves dos veces). El umbral es `type_full_ratio(0.7)`.

##### Liberación de espacio

`package_retrieved` (emitido por el entorno al hacer `retrieve`)
borra el `stored_at` correspondiente y vuelve a llamar
`recompute_shelf_usage(Shelf)`. La cuenta de `shelf_usage` se
deriva por completo de los `stored_at` vivos, así que es imposible
que quede en negativo aunque algún mensaje se haya perdido. Tras
recomputar se emite el snapshot autoritativo para los robots y, si
la shelf cae por debajo del `near_full_ratio` (0.9) y estaba
marcada, `maybe_unmark` la libera. `container_exited` solo limpia
`at_warehouse` (la liberación física de espacio ya la hizo
`package_retrieved`).

##### Snapshot autoritativo a los robots

```jason
+!broadcast_usage_snapshot <-
    .findall(usage(S, W, V), shelf_usage(S, W, V), L);
    .send(robot_light,   tell, shelf_usage_snapshot(L));
    .send(robot_medium,  tell, shelf_usage_snapshot(L));
    .send(robot_heavy,   tell, shelf_usage_snapshot(L));
    .send(robot_heavy2,  tell, shelf_usage_snapshot(L)).
```

Se emite en tres momentos:

1. Tras cada `package_stored` y `package_retrieved`.
2. Al cerrar un ciclo de salida (`exit_cycle_ended`).
3. Periódicamente cada `snapshot_period_ms` (15000 ms por
   defecto), como red de seguridad para cubrir desincronías
   entre eventos. El bucle se lanza con `!!periodic_snapshot`
   desde `+!start` para que viva en una intención independiente.

El supervisor es la **fuente de verdad** dentro del MAS para los
depósitos confirmados. Los robots reciben el snapshot y reemplazan
su `shelf_usage_local`; las reservas locales (`shelf_reservation`)
no se tocan: son creencias propias sobre operaciones en vuelo.

##### Vigilancia temporal del deadline

```jason
+deadline_started(Kind, Types, Duration)[source(scheduler)] <-
    !watch_deadline(Kind, Types, Duration).

+!watch_deadline(Kind, Types, Duration) <-
    .wait(Duration);
    !audit_deadline(Kind, Types).

+!audit_deadline(Kind, Types) <-
    .findall(p(CId, Ty),
             (at_warehouse(CId, Ty, _, _) & .member(Ty, Types)),
             Pending);
    .length(Pending, N);
    !report_audit(Kind, Types, N, Pending).
```

`report_audit` con `N > 0` incrementa `deadline_violations` y
emite `log_event(deadline_missed, CId)` por cada pendiente.

##### Reset al cerrar el ciclo

```jason
+exit_cycle_ended(Group)[source(scheduler)] <-
    .abolish(blocked_group_notified(_));   // ¡todas, no solo la del grupo!
    -exit_cycle_ended(...).
```

Se resetean **todas** las notificaciones porque ambos deadlines
drenaron estanterías y el otro grupo pudo haber sufrido un
no_space que el scheduler descartó por estar en ciclo activo.

##### Errores y conteo

`+total_errors(ErrorType, GlobalTotal)` (percept del entorno):
incrementa contadores y, si supera `max_consecutive_errors`,
imprime un reporte. Hoy `max_consecutive_errors = 999` y
`.stopMAS` está comentado — no detiene realmente el sistema, solo
avisa.

---

### 2.3 Agente `transport` — camión simulado

**Objetivo**: representar al transporte que recoge contenedores
en cada deadline. **No interactúa con el entorno**, solo registra.

```jason
+load_start(Kind, Types)[source(scheduler)] <- ...
+container_shipped(CId, Type)[source(scheduler)] <- ...
+load_end(Kind, N)[source(scheduler)] : total_salidas(T) <-
    -total_salidas(T);
    +total_salidas(T+1).
```

Es el agente más simple: tres planes y un contador de salidas.

---

### 2.4 Robots — `robot_light`, `robot_medium`, `robot_heavy`, `robot_heavy2`

Los cuatro `.asl` de robots son **minimalistas**: declaran
constantes propias e incluyen `mov.asl` (navegación) y `work.asl`
(lógica de trabajo, peer-to-peer y ciclo de salida).

#### 2.4.1 Diferencias por robot

| Robot         | Idle  | maxW | maxSize | timePerMove | priority | is_router | faster_capable                  |
|---------------|-------|------|---------|-------------|----------|-----------|---------------------------------|
| robot_light   | (3,3) | 10   | 1×1     | 100 ms      | 1 (alta) | no        | — (no hay nadie más rápido)     |
| robot_medium  | (4,3) | 30   | 1×2     | 200 ms      | 2        | no        | `W≤1 & H≤1 & Weight≤10` (light) |
| robot_heavy   | (5,3) | 100  | 2×3     | 500 ms      | 3 (baja) | sí        | `W≤1 & H≤2 & Weight≤30` (medium)|
| robot_heavy2  | (6,3) | 100  | 2×3     | 500 ms      | 3        | sí        | `W≤1 & H≤2 & Weight≤30` (medium)|

Cada robot define `can_i_manage(W, H, Weight)` usando **solo sus
topes** (sin mínimos):

```jason
can_i_manage(W, H, Weight) :-
    max_weight(MaxWeight) & max_size(MaxW, MaxH) &
    Weight <= MaxWeight & W <= MaxW & H <= MaxH.
```

La regla **"el robot más rápido capaz se queda con el paquete"**
se aplica en `work.asl` con la guarda `not faster_capable`:

```jason
+container_available(CId, W, H, Weight, Type) :
        can_i_manage(W, H, Weight) &
        not faster_capable(W, H, Weight) &
        not is_router_robot <-
    !enqueue(CId, W, H, Weight, Type);
    .abolish(container_available(CId, _, _, _, _)).
```

`faster_capable(W, H, Weight)` declara la capacidad del robot
**inmediatamente más rápido**:

- light **no la define** → por closed-world, `not faster_capable(...)`
  siempre se cumple → light se queda con todo lo que pueda.
- medium → `W≤1 & H≤1 & Weight≤10` (lo que light puede). Si encaja
  ahí, medium se abstiene.
- heavy / heavy2 → `W≤1 & H≤2 & Weight≤30` (lo que medium puede).
  Si encaja, los heavy se abstienen. Si no, `decide_heavy_peer`
  reparte entre los dos heavy.

Resultado: cada paquete acaba en la cola de UN solo robot — el
más rápido capaz. Light siempre gana cuando puede; medium lo
recoge cuando light no llega; los heavy solo cuando medium
tampoco llega, y entre ellos eligen por carga.

`robot_shelf_priority/1` ordena las estanterías regulares según
preferencia para repartir físicamente la carga:

- light: `[s2, s3, s4, s6, s7, s9]` (cerca → lejos)
- medium: `[s6, s7, s2, s3, s4, s9]` (zona central)
- heavy: `[s9, s6, s7, s2, s3, s4]` (preferencia izquierda y
  capacidad)
- heavy2: `[s9, s7, s6, s4, s3, s2]` (preferencia derecha)

`priority/1` se usa en `mov.asl` para resolver bloqueos: el de
**menor número gana** (light > medium > heavy).

#### 2.4.2 Objetivo y flujo de un robot

**Objetivo**: recoger paquetes, almacenarlos en una estantería
compatible, y durante un deadline retirar los suyos para llevarlos
a la zona de salida.

**Flujo de almacenamiento normal**:

```
container_available    → can_i_manage?     → enqueue
                                            ↓
                            check_idle → process_next
                                            ↓
                                    handle_container
                                            ↓
        query_location  ←  scheduler  →  container_location
                                            ↓
                              choose_shelf_local  (LOCAL)
                                ├─ none → tell unstorable, idle
                                └─ Shelf:
                                            ↓
                       reserve_shelf (broadcast shelf_reserve)
                                            ↓
                                  goto_pos → pickup
                                            ↓
                              navigate_to_shelf → drop_at
                                ├─ ok    → commit_shelf, tell guardado(CId,Shelf,W,V), my_stored, idle
                                └─ fallo → release_shelf, blacklist, retry → ... → force_exit_carried (caso límite)
```

**Flujo del ciclo de salida**:

```
exit_item  →  pick_best_exit_item (más cercano, can_i_manage_weight, can_i_exit)
              ↓
   try_exit_or_fallback (atomic)  →  +exit_in_progress, +pending_claim
              ↓
   .send(scheduler, achieve, claim_exit(CId, Me))
              ↓
       claim_result(CId, granted) → execute_exit
              ↓
   navigate_to_shelf → retrieve → carrying_exit → go_to_exit_cell → drop_at_exit
              ↓
   tell exit_done(CId, Type) → -exit_in_progress → process_next
```

#### 2.4.3 Estados del robot

Manejados con `state/1`:

- `idle`: en zona de descanso o esperando trabajo.
- `going_idle`: navegando hacia idle zone (interrumpible).
- `busy`: ejecutando un ciclo de almacenamiento o salida.

Y un flag transversal:

- `exit_in_progress(CId)`: hay un exit en curso. Bloquea
  `process_next` para no mezclar tareas.
- `carrying_fragile`: paquete frágil en mano → `mov.asl` aplica
  un +15 % al `timePerMove`.
- `carrying_exit(CId, Type, Shelf, W, V)`: paquete del ciclo de
  salida en mano (necesario para re-shelf si el deadline expira).

#### 2.4.4 Planes principales (vía `work.asl`)

**Anuncio de contenedor (no-router):**
```jason
+container_available(CId, W, H, Weight, Type) :
        can_i_manage(W, H, Weight) & not is_router_robot <-
    !enqueue(CId, W, H, Weight, Type);
    .abolish(container_available(CId, _, _, _, _)).

+container_available(CId, W, H, Weight, Type) : not is_router_robot <-
    .abolish(container_available(CId, _, _, _, _)).
```

**Anuncio de contenedor (heavy y heavy2 simétricos):**
```jason
+container_available(CId, W, H, Weight, Type) :
        is_router_robot & can_i_manage(W, H, Weight) <-
    !decide_heavy_peer(CId, W, H, Weight, Type);
    .abolish(container_available(CId, _, _, _, _)).
```

`decide_heavy_peer` envía `achieve report_heavy_info(Me)` al peer,
espera 2 s su `heavy_peer_info(L, S)` y aplica
`route_symmetric` con la regla determinista:
1. cola más corta gana,
2. empate de cola → no ocupado gana sobre busy,
3. empate de cola y ambos no-ocupados → idle gana sobre going_idle,
4. empate absoluto → robot_heavy gana por nombre.

**Encolado (urgentes a la cabeza):**
```jason
+!enqueue(CId, W, H, Weight, urgent) : container_queue(Q) <-
    -container_queue(_);
    +container_queue([pkg(CId, Weight, W, H, urgent) | Q]);
    !check_idle.

+!enqueue(CId, W, H, Weight, Type) : container_queue(Q) <-
    .concat(Q, [pkg(...)], NewQ);
    -container_queue(_);
    +container_queue(NewQ);
    !check_idle.
```

**`check_idle` y `process_next`**: respetan `exit_in_progress`,
priorizan `exit_item` sobre la cola normal cuando el robot está
idle, y caen a `go_idle` si no hay nada.

**`handle_container`**: el plan central. Pide ubicación, elige
estantería local, reserva, recoge, navega y deposita. Si
`drop_at` falla (`-!try_drop`), añade la shelf a la blacklist
local y prueba alternativas; si ninguna cabe, escala a
`force_exit_carried` (caso límite).

**Selección local de estantería:**
- `urgent`: ordena `urgent_shelf` por distancia Manhattan y
  devuelve la primera con hueco (peso+vol contando reservas).
- regulares: usa `robot_shelf_priority` filtrada por
  `regular_shelf` y blacklist.
- `shelf_fits/4` suma `shelf_usage_local` + reservas (`findall +
  sum_rv`) y compara con la capacidad.

**Protocolo de reservas (peer-to-peer):**
- `reserve_shelf` añade `shelf_reservation` y `pending_drop`,
  hace `peer_broadcast(shelf_reserve(CId, Shelf, W, V))`.
- `commit_shelf` (atomic): borra la reserva, actualiza
  `shelf_usage_local` y broadcasteea `shelf_commit`.
- `release_shelf`: borra la reserva y broadcasteea `shelf_release`.
- `retrieved_shelf` (atomic): decrementa `shelf_usage_local` y
  broadcasteea `shelf_retrieved`.

Los handlers de mensajes entrantes (`+shelf_reserve`,
`+shelf_commit`, `+shelf_release`, `+shelf_retrieved`) replican
estos cambios en los otros robots.

**Reconciliación con el supervisor (`shelf_usage_snapshot`):**

```jason
@peer_snapshot[atomic]
+shelf_usage_snapshot(L)[source(supervisor)] <-
    !apply_usage_snapshot(L);
    -shelf_usage_snapshot(L)[source(supervisor)].

+!apply_usage_snapshot([usage(S, W, V) | Rest]) <-
    .abolish(shelf_usage_local(S, _, _));
    +shelf_usage_local(S, W, V);
    !apply_usage_snapshot(Rest).
```

El supervisor difunde periódicamente (y tras cada
`package_stored` / `package_retrieved` / cierre de ciclo) la foto
autoritativa de `shelf_usage`. Cada robot reemplaza su
`shelf_usage_local` con esa foto, eliminando cualquier drift
acumulado por mensajes peer perdidos. Las `shelf_reservation` no
se tocan: son creencias propias del robot sobre operaciones en
vuelo. Si el snapshot llega justo después de un `commit_shelf`
local pero antes de que el supervisor procese el `package_stored`
correspondiente, puede pisar momentáneamente el commit local; el
siguiente snapshot (emitido tras `package_stored`) lo corrige y,
mientras tanto, si el robot subestimara la ocupación el entorno
rechazaría el `drop_at` físico y se reintentaría por la vía normal.

**`finish_task` con tres cláusulas (caso normal, recuperación tras
purga de deadline, catch-all)**: cierra una tarea de almacenamiento
con commit + `tell guardado(CId, Shelf, W, V)` al scheduler +
`+my_stored`. La firma con peso/volumen permite que el supervisor
suba a `stored_at`/`shelf_usage` valores ciertos sin depender del
caché del scheduler. La cláusula catch-all (sin reserva ni
`pending_drop`) sigue enviando la firma legacy `guardado/2` solo a
efectos informativos: el scheduler la registra en `log_pkg` pero
ya **no** emite `package_stored(...,0,0,unknown)` (que era lo que
inflaba con ceros y descuadraba al supervisor en el `retrieve`).

`my_stored(CId, Shelf, W, V)` es **crítico** para el ciclo de
salida: sin él, `can_i_exit` no se cumple y el robot ignora los
exit_item de paquetes que él guardó.

**`go_idle` y `recover_carrying`**: vuelta a la zona de idle y
recuperación best-effort si la tarea murió con paquete en mano
(lo entrega en la salida). `recover_carrying` libera la reserva
(`release_if_reserved(CId)`) **antes** del `drop_at_exit` para
no dejar reservas zombie en el robot ni en los peers — eso
inflaría `shelf_fits` en estanterías que estarían realmente libres.

**Manejo de destrucción de contenedor:**
```jason
+container_destroyed(CId, _) <-
    !remove_from_queue(CId);
    .abolish(container_available(CId, _, _, _, _));
    .abolish(exit_item(CId, _, _, _, _, _));
    .abolish(container_location(CId, _, _));
    .abolish(container_relocated(CId, _, _));
    .abolish(location(CId, _, _));
    .abolish(my_stored(CId, _, _, _));
    .abolish(delegated_stored(CId, _, _, _));
    .abolish(delegating(CId));
    .abolish(pending_drop(CId, _, _, _));
    !release_if_reserved(CId);
    -container_destroyed(CId, _).
```

#### 2.4.5 Planes del ciclo de salida (en `work.asl`)

**Recepción de exit_item:**
```jason
+exit_item(CId, _, W, _, Type, Kind)[source(scheduler)] :
        can_i_manage_weight(W) <-
    !check_idle.
```

**`active_deadline(Kind)` (broadcast del scheduler):** dispara
purga local de reservas en las shelves del grupo (urgentes para
`short`, regulares para `long`) — limpia reservas huérfanas de
operaciones abortadas. Después llama `check_idle`.

**`pick_best_exit_item`:** filtra por `active_deadline(Kind)`,
`can_i_manage_weight`, `can_i_exit` (es propio o delegado o
`at_entry`), y devuelve el más cercano por Manhattan.

**`try_exit_or_fallback` (atomic):** elige el mejor exit_item;
si lo hay, marca `exit_in_progress`, `pending_claim` y envía el
claim. Si no hay nada, intenta el **protocolo de ayuda** entre
peers (más abajo) y, si tampoco, cae al `fallback_to_normal`.

**Respuesta del claim:**
```jason
+claim_result(CId, granted)[source(scheduler)] :
        pending_claim(CId, Loc, Type) <-
    -pending_claim(...);
    !execute_exit(CId, Loc, Type).

+claim_result(CId, denied)[source(scheduler)] :
        pending_claim(CId, _, _) <-
    -exit_in_progress(_);
    -+state(idle);
    !process_next.
```

**`execute_exit/3` con dos variantes:**

- `at_shelf(Shelf)`: navega al shelf, comprueba si el deadline
  sigue activo; si no → `abort_exit_cleanup`. Si sí: `retrieve`,
  marca `carrying_exit`, va a la salida; comprueba el deadline
  otra vez; si expiró con paquete en mano → `reshelf_carried`. Si
  sigue: `drop_at_exit`, `tell exit_done`, libera.
- `at_entry(X, Y)`: idem pero `pickup` en vez de `retrieve`.

**`reshelf_carried`**: usa `choose_shelf_local` para colocar el
paquete en alguna shelf compatible. Si ninguna cabe, escala a
`force_exit_carried`.

**Protocolo de ayuda entre peers (`try_help_then_fallback`):**

Cuando un robot termina su carga del deadline antes que los demás,
en lugar de irse al `fallback_to_normal`, primero pregunta a los
peers si necesitan ayuda. Handshake:

```
A → all : help_request(A, MaxW)
P → A   : help_offer(CId, Shelf, W, V, Type)   (uno por peer)
A → P   : help_take(A, CId)                     (achieve)
P → A   : help_confirm(...) | help_deny(CId)
```

A acepta la oferta más cercana. P solo cede el paquete en
`help_take`, no antes (un offer no aceptado no genera huérfanos).
Si P ya no lo tiene → deny y A vuelve al fallback. `delegating(CId)`
evita re-cesiones.

**Caso límite — `force_exit_carried`:**
```jason
+!force_exit_carried(CId, Type) <-
    !release_if_reserved(CId);
    !go_to_exit_cell(EX, EY);
    drop_at_exit(EX, EY);
    log_event(container_delivered, CId);
    !unmark_fragile;
    .send(scheduler, tell, force_exit_cycle(Type)).
```

`release_if_reserved` es defensivo: aunque el caller usual
(`-!try_drop`) ya libera la reserva antes de escalar, aquí se
asegura de que no quede ninguna `shelf_reservation` para `CId` en
el robot ni en los peers — el paquete sale del sistema sin pasar
por una shelf, así que la reserva no se cerraría por la vía normal
de `commit_shelf`.

#### 2.4.6 Planes de navegación (en `mov.asl`)

**`navigate_to(TX, TY, adjacent(Bool))`:** llegar exacto o quedar
adyacente. La condición de parada se evalúa al inicio de cada
iteración.

**`next_step(CX, CY, TX, TY, NX, NY)`:** decide la siguiente
celda candidata. **Prioriza eje Y** siempre; X solo cuando ya
estamos alineados en Y.

**Validación en 3 pasadas (`choose_valid`):**
1. Pasada 1 (`try_fresh`): no visitado y no `prev_pos` (el óptimo).
2. Pasada 2 (`try_visited`): permite visitados, ordena por
   distancia.
3. Pasada 3 (`try_prev`): permite todo incluido `prev_pos`. Si
   nada vale, falla.

**`try_move`:** espera `timePerMove` (×1.15 si frágil), guarda
`prev_pos` y `visited`, ejecuta `step(NX, NY)`. Si
`error(blocked_by_agent, _)`, llama `handle_block` (resolución
por prioridades + escape perpendicular si insiste).

**`handle_block`:**
- Comparar prioridades: si el otro tiene **mayor prioridad**
  (número menor) → cedo (`escape_move`).
- Si yo tengo más prioridad → espero 200 ms; si tras 3 bloqueos
  no cede → escape.
- Misma prioridad → backoff aleatorio 100–400 ms.

**`navigate_to_shelf(Shelf)`:** pide al entorno
`shelf_adjacent(Shelf, Cells)`, ordena por distancia y va probando
candidatos. Si llega a uno → ok; si no, siguiente.

---

## 3. Interacción con el entorno

### 3.1 Acciones (operations) que un agente puede ejecutar

Todas implementadas en `WarehouseArtifact.executeAction` y
delegadas a `WarehouseModel`. Devuelven `true/false`; en caso de
error añaden un percept `error(Type, Data)` al agente.

| Acción                      | Quién la usa | Qué hace                                             |
|-----------------------------|--------------|------------------------------------------------------|
| `step(X, Y)`                | Robots       | Mueve el robot a (X,Y) si no hay otro robot         |
| `pickup(CId)`               | Robots       | Recoge un contenedor adyacente de la zona inferior  |
| `drop_at(ShelfId)`          | Robots       | Deposita el cargado en una estantería adyacente     |
| `drop_at_exit(EX, EY)`      | Robots       | Deja el cargado en la zona de salida                |
| `retrieve(CId)`             | Robots       | Saca un contenedor almacenado en una shelf adyacente|
| `relocate_container(CId, X, Y)` | Scheduler | Mueve un paquete en clasificación a otra celda      |
| `see`                       | Robots       | Refresca percepts de visión (radio Manhattan = 1)   |
| `get_container_info(CId)`   | Scheduler   | Devuelve `container_info(CId, W, H, Weight, Type)`  |
| `get_shelf_adjacent(SId)`   | Robots      | Devuelve celdas no-shelf adyacentes a un shelf      |
| `block_generation(Type)`    | Scheduler   | Pausa generación del tipo                           |
| `unblock_generation(Type)`  | Scheduler   | Reanuda                                             |
| `log_event(Type, Data)`     | Cualquiera  | Emite línea EVENT en consola y `eventlog.txt`       |

### 3.2 Eventos / percepts del entorno hacia agentes

| Percept                                  | Destinatario       | Cuándo                            |
|------------------------------------------|--------------------|-----------------------------------|
| `new_container(CId)`                     | Todos              | Generador crea contenedor         |
| `at(Robot, X, Y)`                        | Cada robot         | Tras `step` o `see`               |
| `shelf(X, Y)` / `container(C, X, Y)` / `robot(R, X, Y)` | Robot que hizo `see` | Tras `see` |
| `picked(CId)`                            | Robot              | `pickup`/`retrieve` exitoso       |
| `error(Type, Data)`                      | Agente que falló   | Cualquier acción con error        |
| `container_at(CId, X, Y)`                | Scheduler          | Generación + relocate             |
| `occupied(X, Y)`                         | Scheduler          | Cambia ocupación de celda         |
| `container_destroyed(CId, Type)`         | **Todos**          | Robot pisa paquete sin recoger    |
| `container_exited(CId, Type, W, V)`      | Scheduler + Sup.   | `drop_at_exit` exitoso            |
| `package_retrieved(CId, Shelf, W, V)`    | Supervisor         | `retrieve` exitoso                |
| `container_relocated(CId, X, Y)`         | Robots             | Tras `relocate_container`         |
| `container_info(CId, W, H, Weight, Type)`| Quien preguntó    | Tras `get_container_info`         |
| `shelf_adjacent(SId, [pos(X,Y),...])`    | Quien preguntó    | Tras `get_shelf_adjacent`         |
| `total_errors(ErrorType, GlobalTotal)`   | Supervisor        | Cada vez que se acumula un error  |

### 3.3 Hilos y concurrencia del entorno

El generador de contenedores (`startContainerGenerator`) corre en
un `ExecutorService` daemon dedicado (`ContainerGenerator`). Las
acciones de los agentes se ejecutan en los hilos de Jason. Por
eso `blockedGenerationTypes` es un `ConcurrentHashMap.newKeySet()`,
y los maps de `WarehouseModel` (`robots`, `containers`, `shelves`)
son `ConcurrentHashMap`.

### 3.4 Visualización (`WarehouseView`)

Swing puro. Tres paneles: grid (centro), info (derecha) con
estadísticas/robots/shelves, y consola (abajo) con log de actividad
recortado a 500 líneas. Refresco automático cada 1 s.

### 3.5 Logging estructurado

`log_event(Type, Data)` produce líneas con formato fijo:

```
EVENT | time=HH:MM:SS | agent=<agName> | type=<Type> | data=<Data>
```

Volcadas a `System.out` y al fichero `warehouse/eventlog.txt`
(append, con truncado en init). La ruta se resuelve desde el
`warehouse.mas2j` para no depender del CWD.

Tipos típicos emitidos:
- `output_phase_started` (scheduler) — inicio del ciclo.
- `deadline_started` / `deadline_ended` (scheduler).
- `container_delivered` (robot) — al `drop_at_exit`.
- `no_space_detected` (supervisor) — al cruzar el 70 %.
- `deadline_missed` (supervisor) — un paquete no salió a tiempo.

---

## 4. Comportamiento individual de cada robot

Aunque comparten `work.asl` y `mov.asl`, las constantes
diferencian su comportamiento de forma significativa.

### 4.1 `robot_light`

- El **más pequeño y más rápido** (100 ms/paso, prioridad 1).
- `can_i_manage`: `Weight ≤ 10 & W ≤ 1 & H ≤ 1`.
- No define `faster_capable` → por closed-world, **siempre que
  pueda con un paquete, lo encola** (no hay robot más rápido a
  quien cederlo).
- Prefiere las shelves más pequeñas (S2..S4) por proximidad y
  porque las grandes tienen más sentido para los pesados.
- En `mov.asl` *gana* casi todos los duelos de paso, así que
  raramente cede.

### 4.2 `robot_medium`

- Velocidad media (200 ms/paso, prioridad 2).
- `can_i_manage`: `Weight ≤ 30 & W ≤ 1 & H ≤ 2` (solo topes).
- `faster_capable(W,H,Weight) :- W ≤ 1 & H ≤ 1 & Weight ≤ 10`
  (capacidad de light). Si el paquete encaja en light, medium
  se **abstiene** automáticamente vía `not faster_capable` en
  `+container_available`.
- En la práctica, medium acaba con paquetes de tamaño 1×2
  (cualquier peso ≤30) y de tamaño 1×1 con peso entre 11 y 30 kg.
- Prefiere las shelves intermedias (S6, S7) por ser las
  centrales en altura y de capacidad media.

### 4.3 `robot_heavy` y `robot_heavy2`

- Lentos (500 ms/paso, prioridad 3) — siempre ceden el paso a
  light y medium.
- `can_i_manage`: `Weight ≤ 100 & W ≤ 2 & H ≤ 3` (solo topes).
- `faster_capable(W,H,Weight) :- W ≤ 1 & H ≤ 2 & Weight ≤ 30`
  (capacidad de medium). Si el paquete encaja en medium (lo cual
  incluye también lo que cabe en light), los heavy se **abstienen**.
- Ambos llevan el flag `is_router_robot`, así que el plan reactivo
  de `+container_available` no encola directamente sino que
  ejecuta `decide_heavy_peer` (consulta al peer + regla simétrica
  determinista). Solo uno de los dos se queda cada paquete.
- `robot_heavy` prefiere shelves de la izquierda (S9 primero por
  capacidad, luego S6, S7…); `robot_heavy2` prefiere flanco
  derecho (S9, S7, S6…). Reparto físico que minimiza colisiones
  en el almacén central.
- En `route_symmetric` el desempate por nombre va a favor de
  `robot_heavy` (caso (4)), pero la regla 1 (cola más corta) y
  la 2 (no-busy gana) son las que decide en la práctica.

### 4.4 Particiones de capacidad — visión conjunta

La regla `can_i_manage & not faster_capable` produce una
**partición disjunta**: cada paquete acaba en la cola de UN solo
robot (o de uno de los dos heavy tras `decide_heavy_peer`).

Quién acaba con cada perfil de paquete:

| Tamaño / Peso         | Quién lo procesa                          |
|-----------------------|-------------------------------------------|
| 1×1, ≤ 10 kg          | light                                     |
| 1×1, 11–30 kg         | medium (light no puede por peso)          |
| 1×1, 31–100 kg        | heavy / heavy2 (medium no por peso)       |
| 1×2, ≤ 30 kg          | medium (light no puede por tamaño H=2)    |
| 1×2, 31–100 kg        | heavy / heavy2                            |
| 2×2 o 2×3, ≤ 100 kg   | heavy / heavy2 (medium no por tamaño W=2) |

La partición es **disjunta**: si un paquete cabe en un robot
rápido, los más lentos lo ignoran de entrada y no malgastan
ciclos encolando algo que nunca llegarán a procesar.

---

## 5. Comunicaciones y diálogos entre agentes

### 5.1 Resumen visual (mensajes principales)

```
ENV ──> scheduler:  +new_container, +container_at, +occupied,
                    +container_exited, +container_destroyed
ENV ──> supervisor: +package_retrieved, +container_exited,
                    +container_destroyed, +total_errors
ENV ──> robots:     +at, +shelf, +robot, +container, +picked,
                    +container_destroyed, +container_relocated,
                    +error

scheduler ──> robot_*: tell container_available(CId, W, H, Weight, Type)
                       tell container_location(CId, X, Y)
                       tell exit_item(CId, Loc, W, V, Type, Kind)
                       tell active_deadline(Kind)         (broadcast)
                       untell active_deadline(Kind)        (broadcast)
                       tell exit_taken(CId)                (broadcast)
                       tell claim_result(CId, granted|denied)
                       untell exit_item / container_available (limpieza)

robot_* ──> scheduler: achieve provide_location(CId, Me)
                       achieve claim_exit(CId, Me)
                       tell unstorable(CId, Type)
                       tell guardado(CId, Shelf, W, V)         (firma con peso/vol)
                       tell guardado(CId, Shelf)               (firma legacy, solo log)
                       tell exit_done(CId, Type)
                       tell force_exit_cycle(Type)

scheduler ──> supervisor: tell package_arrived(CId, W, V, Type)
                          tell package_stored(CId, Shelf, W, V, Type)
                          achieve list_stored(Types, Kind)
                          tell deadline_started(Kind, Types, Duration)
                          tell exit_cycle_started
                          tell exit_cycle_ended(Group)

supervisor ──> scheduler: tell stored_list_response(Kind, L)
                          tell no_space(Type)
                          tell shelf_full(S) / shelf_free(S)

supervisor ──> robot_*:   tell shelf_usage_snapshot(L)
                          (foto autoritativa de shelf_usage; los robots
                           reemplazan su shelf_usage_local con esta L)

scheduler ──> transport:  tell load_start(Kind, Types)
                          tell container_shipped(CId, Type)
                          tell load_end(Kind, N)

robot_* <──> robot_*:  tell shelf_reserve / shelf_commit /
                            shelf_release / shelf_retrieved
                       achieve report_heavy_info(Me)         (heavy↔heavy2)
                       tell heavy_peer_info(L, S)
                       tell help_request(A, MaxW)
                       tell help_offer(CId, S, W, V, Type)
                       achieve help_take(A, CId)
                       tell help_confirm(...)|help_deny(CId)
```

### 5.2 Diálogos en detalle

#### 5.2.1 Anuncio de un nuevo contenedor

```
ENV  → scheduler:  +new_container(c_5)
SCH  → ENV:        get_container_info(c_5)
ENV  → scheduler:  +container_info(c_5, 1, 2, 25, standard)
SCH  → supervisor: tell package_arrived(c_5, 25, 2, standard)
SCH  → robot_*:    tell container_available(c_5, 1, 2, 25, standard)
```

Cada robot evalúa `can_i_manage & not faster_capable`:

- **light**: `can_i_manage` falla (Weight=25 > 10) → segundo
  plan abolish, sin encolar.
- **medium**: `can_i_manage` cumple, `faster_capable` falla
  (Weight=25 > 10 → light no puede) → encola c_5.
- **heavy / heavy2**: `can_i_manage` cumple, pero
  `faster_capable` cumple (W=1, H=2, Weight=25 ≤ 30 → medium
  puede) → segundo plan abolish, sin encolar y sin invocar
  `decide_heavy_peer`.

Resultado: **solo medium tiene c_5 en cola**. Los heavy ni
siquiera llegan a hablar entre ellos para este paquete. La
partición es disjunta — el paquete se asigna automáticamente
al robot más rápido capaz.

> Si en lugar de un 1×2/25kg cayera un 2×3/80kg:
> light y medium fallarían en `can_i_manage` (W=2 fuera de
> tope). heavy y heavy2 cumplen `can_i_manage` y NO cumplen
> `faster_capable` (W=2 > 1 → medium no puede). Ambos invocan
> `decide_heavy_peer` y se reparten el paquete según cola/estado.

#### 5.2.2 Recogida y almacenamiento

```
ROB  → scheduler:  achieve provide_location(c_5, robot_medium)
SCH  → robot:      tell container_location(c_5, 6, 1)
ROB  → ROB(local): elige shelf_2 (cabe) → reserve_shelf
ROB  → robot_*:    tell shelf_reserve(c_5, shelf_2, 25, 2)
ROB  → ENV:        step, step, ..., pickup(c_5)
ROB  → ENV:        step, step, ..., drop_at(shelf_2)
ROB  → robot_*:    tell shelf_commit(c_5, shelf_2, 25, 2)
ROB  → scheduler:  tell guardado(c_5, shelf_2, 25, 2)
SCH  → supervisor: tell package_stored(c_5, shelf_2, 25, 2, standard)
SUP  → SUP:        +stored_at, recompute_shelf_usage(shelf_2),
                   check_type_space, broadcast_usage_snapshot
SUP  → robot_*:    tell shelf_usage_snapshot([usage(shelf_1,0,0),
                                              usage(shelf_2, 25, 2), ...])
```

Si `check_type_space` cruza el 70 %:
```
SUP  → scheduler:  tell no_space(standard)
```

#### 5.2.3 Inicio de ciclo de salida

Disparado por `no_space(standard)` (grupo `normal`):

```
SCH:  +exit_cycle_active, +trigger_group(normal), +blocked_group(normal)
SCH  → ENV:         block_generation(standard), block_generation(fragile)
SCH  → supervisor:  tell exit_cycle_started
SCH  → log:         log_event(output_phase_started, normal)
SCH:  +active_deadline(long), +deadline_shipped_count(long, 0)
SCH  → log:         log_event(deadline_started, normal)
SCH  → transport:   tell load_start(long, [standard, fragile])
SCH  → supervisor:  tell deadline_started(long, [standard, fragile], 90000)
SCH  → robot_*:     tell active_deadline(long)               (broadcast)

SCH  → supervisor:  achieve list_stored([standard, fragile], long)
SUP  → scheduler:   tell stored_list_response(long, [s(c_3, shelf_2, ...), ...])

por cada paquete:
SCH  → robot_*:     tell exit_item(c_3, at_shelf(shelf_2), 25, 2, standard, long)

(unstorable y pending_announce cosechados como at_entry)

SCH:                .wait(90000)  ← cuerpo del deadline
```

Los robots reaccionan al `+active_deadline(long)` purgando
reservas en regular shelves y haciendo `check_idle`. Cada robot
con `state(idle)` y al menos un `exit_item` válido:

```
ROB  → ROB(local): pick_best_exit_item(Best)
ROB:               +exit_in_progress(c_3), +pending_claim(c_3, ...)
ROB  → scheduler:  achieve claim_exit(c_3, robot_medium)

SCH  → robot:      tell claim_result(c_3, granted)
SCH  → robot_*:    tell exit_taken(c_3)        (broadcast, los demás abolishen)

ROB  → ENV:        step,..., retrieve(c_3)
ROB  → robot_*:    tell shelf_retrieved(c_3, shelf_2, 25, 2)
ROB  → ENV:        step,..., drop_at_exit(0, 0)
ROB  → log:        log_event(container_delivered, c_3)
ROB  → scheduler:  tell exit_done(c_3, standard)

SCH  → transport:  tell container_shipped(c_3, standard)
SCH:               -pending_exit, -claimed
SCH  → robot_*:    untell exit_taken(c_3)
```

Al cumplirse los 90 s:

```
SCH:               -active_deadline(long)
SCH  → log:        log_event(deadline_ended, normal)
SCH  → transport:  tell load_end(long, N)
SCH  → robot_*:    untell active_deadline(long)
SCH  → robot_*:    untell exit_item(...)         (limpieza no consumidos)

SCH:               !end_exit_cycle(normal)
SCH  → ENV:        unblock_generation(standard), unblock_generation(fragile)
SCH  → supervisor: tell exit_cycle_ended(normal)
SCH:               flush pending_announce (publica a robots)
SCH:               chain_or_release → -exit_cycle_active si la cola está vacía
```

#### 5.2.4 Diálogo heavy ↔ heavy2 (reparto simétrico)

```
SCH  → heavy:   tell container_available(c_8, 2, 3, 80, standard)
SCH  → heavy2:  tell container_available(c_8, 2, 3, 80, standard)

heavy:  +container_available(c_8,...) [is_router_robot, can_i_manage] →
        !decide_heavy_peer
heavy2: idem

heavy   → heavy2:  achieve report_heavy_info(robot_heavy)
heavy2  → heavy:   tell heavy_peer_info(0, idle)        ← cola=0, idle
heavy   → heavy2:  achieve report_heavy_info(robot_heavy2)  (en paralelo)
heavy   → heavy:   tell heavy_peer_info(2, busy)        ← cola=2, busy

decide_heavy_peer en heavy:
   MyL=2, PeerL=0 → MyL > PeerL → "descarto c_8"
decide_heavy_peer en heavy2:
   MyL=0, PeerL=2 → MyL < PeerL → enqueue(c_8)
```

Resultado: solo heavy2 lo encola, sin solapamientos.

#### 5.2.5 Protocolo de ayuda durante un deadline

Termina su carga propia un robot rápido (light) antes que los
heavies; light pregunta:

```
light  → heavy/heavy2/medium:  tell help_request(robot_light, 10)
heavy  → light:                tell help_offer(c_4, shelf_2, 8, 1, standard)
                              (de su my_stored, que light puede cargar)
                              (espera 800 ms para juntar ofertas)
light:  pick_closest_offer (Manhattan a la shelf de cada oferta)
light  → heavy:               achieve help_take(robot_light, c_4)

heavy:  +help_take(...) [my_stored(c_4, shelf_2, 8, 1) & not delegating(c_4)] →
        +delegating(c_4); -my_stored(c_4, shelf_2, 8, 1);
        ?exit_item(c_4, _, _, _, Type, _);
heavy  → light:               tell help_confirm(c_4, shelf_2, 8, 1, standard)
heavy:  -delegating(c_4)

light:  +help_confirm(...) → +delegated_stored(c_4, shelf_2, 8, 1);
        !try_exit_or_fallback   ← ahora lo coge como cualquier exit_item suyo
```

Si heavy ya no tiene `c_4` (lo cogió en paralelo o lo cedió ya),
manda `help_deny(c_4)` y light cae a `fallback_to_normal`.

---

## 6. El ciclo de salida — caso central

Esta sección es la columna vertebral de esta iteración. Aquí
tienes los flujos típicos en formato detallado, con un caso de
éxito completo y varios casos de fracaso/recuperación.

### 6.1 Vista lineal del ciclo

```
T0:  trigger (no_space | umbral unstorable | force_exit_cycle)
     ├─ +exit_cycle_active
     ├─ +trigger_group(Group)
     ├─ block_generation(...)
     ├─ tell exit_cycle_started al supervisor
     └─ +active_deadline(Kind) → broadcast
        ├─ supervisor arranca watch_deadline
        ├─ scheduler pide list_stored y publica exit_item
        └─ robots reaccionan (purga reservas, check_idle)

T0..T0+Duration:
     - robots compiten por exit_items vía claim
     - cada drop_at_exit → exit_done → container_shipped
     - help_request/offer cuando un robot termina pronto

T0+Duration:
     - close_deadline: -active_deadline, untell, abolish exit_items
     - tell load_end(Kind, N) a transport
     - supervisor.audit_deadline: cuenta pendientes y log_event(deadline_missed, ...)
     - end_exit_cycle: unblock, flush pending_announce, chain_or_release
```

### 6.2 Caso de ÉXITO completo (deadline `long`)

**Estado inicial**: 
- shelf_2: 1 paquete (c_3, 25 kg)
- shelf_3: 2 paquetes (c_4 30 kg, c_7 18 kg)
- shelf_6: 1 paquete (c_9 50 kg)
- Total grupo normal: 123/300 kg, 4/52 u — todavía bajo el 70 %.

Cae c_11 (40 kg standard). Se almacena en shelf_2: ahora
shelf_2: 65/50 kg (rebasa near_full_ratio), shelf_2 marcada
"casi tope". Total grupo: 163/300 kg = 54.3 %. Bajo umbral todavía.

Cae c_12 (50 kg standard). Heavy lo coloca en shelf_9: 50/200 kg,
3/20 u. Total grupo: 213/300 = 71 % → **¡cruza umbral!**

```
SUP:  blocked_group_notified(normal) NO existe → comprueba
      sum_group_usage(normal, 213, 8, 300, 52) → 213/300 = 0.71 ≥ 0.7
      +blocked_group_notified(normal)
      log_event(no_space_detected, standard)
SUP  → scheduler:  tell no_space(standard)

SCH:  +exit_cycle_active, +trigger_group(normal)
      → block_generation(standard), block_generation(fragile)
      → tell exit_cycle_started
      → +active_deadline(long), broadcast tell active_deadline(long)
      → tell load_start(long, [standard, fragile]) a transport
      → tell deadline_started(long, [standard, fragile], 90000) a supervisor
      → achieve list_stored([standard, fragile], long) a supervisor
SUP  → scheduler:  tell stored_list_response(long, [s(c_3, shelf_2, 25, 2, standard),
                                                    s(c_4, shelf_3, 30, 2, standard),
                                                    s(c_7, shelf_3, 18, 1, standard),
                                                    s(c_9, shelf_6, 50, 4, fragile),
                                                    s(c_11, shelf_2, 40, 1, standard),
                                                    s(c_12, shelf_9, 50, 3, standard)])
SCH:  para cada uno → tell exit_item(...) a los 4 robots, +pending_exit
```

Los 4 robots reaccionan a `+active_deadline(long)`:

- **light** (en (3,3) idle): purga reservas regulares, check_idle.
  pick_best_exit_item devuelve c_7 (18 kg, 1×1, más cercano →
  shelf_3 a Manhattan 11). c_4 también es 1×2, pero pesa 30 kg
  > 10 → no manage.
- **medium** (en (4,3) idle): pick_best_exit_item considera
  todos. Por distancia y por can_i_manage: c_4 (30 kg, 1×2, en
  shelf_3 a 11). c_7 también, pero light va a por él. Aplicará
  `claim_exit` y el scheduler resolverá.
- **heavy** (en (5,3) idle): pick_best_exit_item: c_11 (40 kg,
  1×1, shelf_2 a 9), c_3 (25 kg, 1×2, shelf_2), c_9 (50 kg,
  4 vol, shelf_6), c_12 (50 kg, 3 vol, shelf_9). El más cercano
  que cumple `can_i_exit` (tiene `my_stored(c_11, shelf_2,...)`
  porque él lo guardó) → c_11.
- **heavy2** (en (6,3) idle): tiene `my_stored(c_12, shelf_9,...)`
  y `my_stored(c_9, shelf_6,...)` (digamos). c_9 más cerca → c_9.

```
light  → scheduler:  achieve claim_exit(c_7, robot_light)
medium → scheduler:  achieve claim_exit(c_4, robot_medium)
heavy  → scheduler:  achieve claim_exit(c_11, robot_heavy)
heavy2 → scheduler:  achieve claim_exit(c_9, robot_heavy2)

SCH (cuatro intenciones, sin solapes):
  +claimed(c_7) → tell claim_result(c_7, granted) a light, broadcast tell exit_taken(c_7)
  +claimed(c_4) → idem para medium
  +claimed(c_11) → idem para heavy
  +claimed(c_9) → idem para heavy2
```

Cada uno ejecuta `execute_exit(CId, at_shelf(S), Type)`:
navega a la shelf, comprueba `active_deadline(_)`, `retrieve(CId)`,
marca `carrying_exit`, va a `go_to_exit_cell` (la celda libre más
cercana de la zona de salida), `drop_at_exit(EX, EY)`,
`log_event(container_delivered, CId)`, `tell exit_done`.

Tiempos aproximados (light a 100 ms/paso, medium 200, heavy 500):
- light: ~25 pasos = 2.5 s viaje + retrieve + 25 pasos vuelta ≈ 5 s.
- medium: ~10 s.
- heavy/heavy2: ~25 s cada uno.

Cuando light termina c_7 (5 s) sigue habiendo c_3, c_12 en cola
sin owner. light no tiene `my_stored` para esos pero tampoco
puede cargar c_12 (50 kg). Para c_3 (25 kg) tampoco
(`can_i_manage_weight(25)` con max=10 → falla). Por
`can_i_exit/2` solo le valdría algo `at_entry`. → `try_help_then_fallback`:

```
light  → broadcast: tell help_request(robot_light, 10)
heavy  → light:     tell help_offer(c_3, shelf_2, 25, 2, standard)
                    (no, 25>10 → no) — heavy busca con W <= 10
medium → light:     tell help_offer(... — algo que medium guardó y pese ≤10)
                    (probablemente nada cumple — medium no acepta ≤10)
heavy2 → light:     tell help_offer(...)
```

Si nadie ofrece (porque ningún `my_stored` cumple W ≤ 10):
`consume_help_offer(none)` → `fallback_to_normal` → si no hay
nada en la cola normal → `go_idle`. Light vuelve a su idle zone
y se pone a esperar.

Mientras, medium termina c_4 (~10 s). `pick_best_exit_item`
podría devolver c_3 (25 kg ≤ 30, my_stored si fue medium quien
lo almacenó). Si lo cogió heavy en su día, medium no tiene
`my_stored(c_3,...)` y `can_i_exit(c_3, at_shelf(shelf_2))` falla.
→ help_request → heavy ofrece c_3 → medium acepta y lo retira.

Heavy y heavy2 siguen con c_11 y c_9 → c_12 a continuación.
Total entregados al cumplirse 90 s: los 6 paquetes.

```
T0+90s:
SCH:  -active_deadline(long), tell load_end(long, 6) a transport
SUP.audit_deadline(long, [standard, fragile]):
   .findall(at_warehouse(CId, Ty, _, _) where Ty in [standard, fragile])
   → vacío (todos salieron) → "deadline cumplido (sin pendientes)"
SCH:  end_exit_cycle(normal)
   → unblock_generation(standard), unblock_generation(fragile)
   → tell exit_cycle_ended(normal) a supervisor
   → flush pending_announce (si hubo paquetes durante el bloqueo)
   → chain_or_release → cola vacía → -exit_cycle_active
SUP:  +exit_cycle_ended(normal) → .abolish(blocked_group_notified(_))
```

Sistema vuelve a modo normal. Cualquier paquete que haya
intentado generarse durante el bloqueo (con generación duplicada
en intervalo: 10–20 s en lugar de 5–10 s) reaparece en la cola
de generación tras `unblock`.

### 6.3 Caso de FRACASO 1 — paquetes no entregados a tiempo

Mismo escenario pero **2 robots heavy bloqueados** por un atasco
en el pasillo central durante 30 s (escape perpendicular falla
porque hay shelves). Heavy2 acaba c_9 a tiempo, pero c_12 no se
ha terminado de mover cuando expira el deadline.

```
T0+90s:
SCH:  close_deadline(long) → tell load_end(long, 5)   ← solo 5
SUP.audit_deadline(long, [standard, fragile]):
   .findall(at_warehouse(c_12, standard, 50, 3))     ← c_12 sigue en almacén
   "ERROR INFORMATIVO | deadline=long | tipos=[standard, fragile]"
   "Contenedores sin entregar al expirar: 1"
   "Lista: [p(c_12, standard)]"
   "Total incumplimientos acumulados: 1"
   log_event(deadline_missed, c_12)
   deadline_violations: 0 → 1
```

El paquete c_12 sigue almacenado en shelf_9 con
`my_stored(c_12, shelf_9, 50, 3)` en heavy2. Si en el siguiente
deadline `normal` el scheduler vuelve a pedir `list_stored`,
c_12 aparece de nuevo y heavy2 lo retira esa vez.

**¿Y si heavy2 estaba con `carrying_exit` cuando expiró el
deadline?** Al comprobar `if (not active_deadline(_))` antes del
`drop_at_exit`, entra en `reshelf_carried`: vuelve a meter c_12
en una shelf compatible. No se pierde. En el próximo deadline el
supervisor lo ve de nuevo en su `stored_at`.

### 6.4 Caso de FRACASO 2 — `claim_exit` denegado por carrera

Dos robots eligen el mismo `exit_item` casi simultáneamente:

```
heavy  → scheduler:  achieve claim_exit(c_11, robot_heavy)
heavy2 → scheduler:  achieve claim_exit(c_11, robot_heavy2)

SCH:  primero llega heavy (orden Jason no determinista pero
      atómico por intención):
      +claimed(c_11) → tell claim_result(c_11, granted) a heavy
                     → broadcast tell exit_taken(c_11)
      cuando llega claim_exit de heavy2:
      not claimed(c_11) FALLA → catch-all
      → tell claim_result(c_11, denied) a heavy2

heavy2:  +claim_result(c_11, denied)[source(scheduler)] :
              pending_claim(c_11, _, _) <-
         -pending_claim(c_11, _, _);
         .abolish(exit_item(c_11, _, _, _, _, _));
         -exit_in_progress(_);
         -+state(idle);
         !process_next.

         (process_next vuelve a try_exit_or_fallback con la lista
         actualizada — c_11 ya no está)
```

Limpio. El sistema sigue.

### 6.5 Caso de FRACASO 3 — robot pisa un paquete

heavy va navegando y por azar pisa c_18 que el generador acaba
de crear en la celda (5,1):

```
ENV (executeSteap → escacharPaquete):
   detecta c_18 en la posición destino, lo destruye
   addPercept(scheduler, broadcast container_destroyed(c_18, urgent))
   addError(heavy, "splash_container", ...)
   El step se considera ÉXITO (heavy se mueve, no pierde la intención)

SCH: +container_destroyed(c_18, urgent) →
   .abolish(package_info(c_18, _, _, _));
   .abolish(pending_announce(c_18, _, _, _, _));
   .abolish(claimed(c_18));
   .abolish(pending_exit(c_18, _, _, _, _, _));
   .abolish(container_at(c_18, _, _));
   !remove_from_unstorable(c_18);
   .broadcast(untell, exit_item(c_18, ...));
   .broadcast(untell, container_available(c_18, _, _, _, _));
   .broadcast(untell, exit_taken(c_18));

SUP: +container_destroyed(c_18, urgent) → .abolish(at_warehouse(c_18, _, _, _))
ROB: +container_destroyed(c_18, _) →
   !remove_from_queue(c_18);
   .abolish(...todas las referencias...);
   !release_if_reserved(c_18);
```

El paquete desaparece limpiamente de todo el sistema. Nadie se
queda con referencias huérfanas.

### 6.6 Caso de FRACASO 4 — robot con paquete en mano y deadline expirado

medium retiró c_4 del shelf_3 a falta de 5 s para que termine el
deadline. Va de camino a la salida, pero está a 8 pasos
(~1.6 s × 8 = 12.8 s). Antes de llegar:

```
Justo antes de drop_at_exit:
   if (not active_deadline(_)) ← VERDADERO, ya expiró
   → !reshelf_carried(c_4, standard, shelf_3, 30, 2)
   → choose_shelf_local(c_4, standard, 30, 2, Chosen)
       (las shelves regulares fueron drenadas → todas tienen hueco)
       → Chosen = shelf_2 (la primera que cumpla en su orden)
   → reserve_shelf, navigate_to_shelf(shelf_2), try_reshelf_drop
   → drop_at(shelf_2) → ok → commit + tell guardado + +my_stored
```

Resultado: c_4 vuelve almacenado en shelf_2 (puede ser distinta a
la original). En el próximo deadline `normal` el supervisor lo
verá en `stored_at` y lo publicará.

> **Importante**: si `choose_shelf_local` no encuentra ninguna
> shelf que admita el paquete (caso patológico tras un drenaje
> incompleto), `reshelf_carried_dispatch(_, none)` dispara
> `force_exit_carried`: lleva el paquete a la salida fuera del
> deadline y pide al scheduler `force_exit_cycle(Type)`. Es el
> caso límite, pero el sistema no se queda con paquete huérfano.

### 6.7 Caso de FRACASO 5 — robot no encuentra shelf desde el principio

Caen 4 paquetes urgent seguidos (1×1, 5 kg cada uno) cuando las
3 urgent shelves (S1, S5, S8) ya estaban llenas al 90 % por uno
gigante en cada (raro pero posible). Light intenta encolar el
primero:

```
medium → ROB(local): choose_shelf_local(c_2, urgent, 5, 1, Chosen)
   → urgent_shelf ordenadas por distancia, comprobando shelf_fits
   → S1: 50+5 > capacidad ✗
   → S5: 100+5 > capacidad ✗
   → S8: 200+5 > capacidad ✗
   → Chosen = none
medium → scheduler: tell unstorable(c_2, urgent)

SCH: +unstorable(c_2, urgent) → record_unstorable(c_2, urgent)
   unstorable_pending(urgent, [c_2])  (1 pendiente)
   check_unstorable_threshold(urgent, 1) → < 3 → no acción

(igual con c_3, c_4)
SCH: tras el 3º →
   unstorable_pending(urgent, [c_4, c_3, c_2])  (3 pendientes)
   check_unstorable_threshold(urgent, 3) ≥ 3 →
   begin_exit_cycle(urgent)
```

Arranca el deadline `short` (30 s, solo urgentes). El scheduler
publica `exit_item(c_X, at_shelf(S1), ...)` por cada paquete
almacenado y `exit_item(c_2, at_entry(5, 0), ...)` por cada
unstorable. Los robots los procesan en paralelo. Los robots
**al recoger desde at_entry no necesitan `my_stored`** —
`can_i_exit(_, at_entry(_,_))` es siempre cierto.

### 6.8 Diagrama de transición simplificado del scheduler durante el ciclo

```
            new_container/no_space/unstorable/force
                            │
                            ▼
                    ┌─────────────────┐
   pending_queue ── │ exit_cycle_      │ ── lock activo
   FIFO+dedup       │ active           │
                    └────────┬────────┘
                             │
                  ┌──────────▼──────────┐
                  │ run_one_deadline    │
                  │ (urgent o normal)   │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │ active_deadline +   │
                  │ publish stored +    │
                  │ publish unstorable  │
                  │   .wait(Duration)   │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │ close_deadline:     │
                  │ untell active,      │
                  │ untell exit_items   │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │ end_exit_cycle:     │
                  │ unblock + flush     │
                  └──────────┬──────────┘
                             │
                  ┌──────────▼──────────┐
                  │ chain_or_release    │
                  └─────────────────────┘
                  /                    \
        [pending_queue ≠ []]      [pending_queue = []]
        run_one_deadline(Next)    -exit_cycle_active
```

---

## 7. Decisiones importantes de diseño

### 7.1 Entorno "tonto", razonamiento en agentes

`WarehouseArtifact` no decide nada de coordinación. Si dos
robots quieren ir a la misma celda, devuelve `error(blocked_by_agent)`
y los robots se las arreglan vía `priority + handle_block`.

**Por qué**: separar mecánica de política. La política puede
cambiar (otra heurística de pathfinding, otra prioridad de
shelves) sin tocar Java.

**Alternativa descartada**: un planificador centralizado en Java
que reparta tareas óptimamente. Sería más eficiente pero rompería
el espíritu BDI y la modularidad.

### 7.2 Ciclo de salida disparado, no continuo

El sistema almacena hasta el 70 % y entonces vacía. No hay
salida continua.

**Por qué**: para poder usar deadlines cerrados — durante
`active_deadline(long)` los robots solo sacan no-urgentes; durante
`active_deadline(short)` solo urgentes. Esto cumple el spec del
enunciado y permite al supervisor auditar incumplimientos.

**Alternativa**: salida continua con prioridad por antigüedad.
Más natural pero no se puede medir "deadline missed".

### 7.3 Cola FIFO + lock `exit_cycle_active`

`pending_queue` con dedup permite encadenar deadlines sin perder
triggers, y `chain_or_release` evita la ventana de carrera de
`-exit_cycle_active; ...; +exit_cycle_active`.

**Problema que resuelve**: si llegan dos `no_space` casi
simultáneos para grupos distintos (`urgent` y `normal`), no
arrancan dos ciclos en paralelo. El primero ejecuta y el segundo
queda en cola.

### 7.4 Estado de shelves duplicado intencionadamente

Cada robot lleva `shelf_usage_local` + `shelf_reservation`; el
supervisor lleva `shelf_usage` autoritativo (derivado de
`stored_at`).

**Por qué**: los robots eligen shelf en local sin esperar
round-trip. Las reservas peer-to-peer (`shelf_reserve`,
`shelf_commit`, etc.) sincronizan los locales optimistamente.

**Antidrift en dos capas:**

1. **Recomputación, no acumulación.** El supervisor no mantiene
   `shelf_usage` con sumas/restas evento a evento. Lo deriva de
   `stored_at` tras cada `package_stored`/`package_retrieved`. Un
   evento perdido afecta a un único contenedor y no se compone con
   errores futuros — es imposible que `shelf_usage` quede negativo
   o que el drift crezca con el tiempo.
2. **Snapshot autoritativo.** Tras cada cambio, al cerrar un ciclo
   de salida y periódicamente (cada `snapshot_period_ms` =
   15000 ms) el supervisor difunde
   `shelf_usage_snapshot([usage(S, W, V), ...])` a los 4 robots,
   que reemplazan su `shelf_usage_local`. Las
   `shelf_reservation` (operaciones en vuelo del propio robot) NO
   se tocan. Así, cualquier desincronía de los mensajes peer entre
   robots se corrige al siguiente snapshot.

**Riesgo residual**: si el `stored_at` del supervisor diverge del
estado real Java (porque algún `package_stored` o
`package_retrieved` no llegara), la reconciliación entre agentes
converge a algo coherente entre ellos pero no necesariamente igual
al entorno. Cerrar ese hueco al 100 % requeriría una acción de
lectura en el entorno (descartada por el principio de entorno
delgado).

### 7.5 Robots heavy simétricos (no leader-follower)

`is_router_robot` aplica a ambos heavies; ambos ejecutan
`decide_heavy_peer` con la misma regla determinista. Por eso solo
uno se queda cada paquete.

**Por qué**: tolerancia a fallos — si uno cae, el otro sigue
recibiendo `container_available` (que en realidad sigue llegando a
ambos siempre). El protocolo simétrico no necesita un "líder".

### 7.6 Prioridad de eje Y en `next_step`

Los pasillos del almacén son horizontales (filas de shelves a
y=2,3 / 6,7 / 10,11,12). Subir antes que avanzar lateralmente
evita atravesar pasillos congestionados.

**Por qué no "mayor delta primero"**: el greedy con mayor delta
se atascaba probando entrar entre dos shelves de la misma fila.
Probado y descartado.

### 7.7 IDs como átomos sin comillas

`removePerceptsByUnif` y `Literal.parseLiteral("container_X")`
producen átomos. El `replace("\"", "")` en `executePickup` etc. es
para soportar invocaciones del .asl tanto si pasaron string como
si pasaron átomo, pero internamente todo es átomo.

**Por qué importa**: si los IDs llegasen como strings, los
`?container_at(c_5, X, Y)` no unificarían con
`container_at("c_5", X, Y)` y se romperían planes silenciosamente.

### 7.8 Ventana fija de 800 ms para help_offers

`ask_for_help` espera 800 ms para juntar ofertas antes de elegir.

**Por qué un timeout fijo**: Jason no permite OR en `.wait`. Una
alternativa con `.wait({+help_offer(...)}, 800, _)` solo capturaría
la primera oferta. Con timeout fijo se recogen todas y se elige
la mejor.

### 7.9 `pending_drop` sobrevive a la purga de reservas

La purga al `+active_deadline` borra `shelf_reservation` pero
**no** `pending_drop`. Razón: si un drop está a medias cuando
arranca el deadline, `finish_task` necesita W,V para hacer
`commit_shelf` aunque la reserva ya no exista. La cláusula de
recuperación (`pending_drop` cae si no hay reservation) cubre
esa ventana.

### 7.10 No detención automática del MAS por errores

`max_consecutive_errors(999)` y `.stopMAS` está comentado en
supervisor. Razón pragmática: durante el desarrollo se prefiere
ver los logs hasta el final. Para entrega final podría bajarse
a un límite más realista y descomentar.

---

## 8. Gestión de errores y robustez

### 8.1 Errores nominales del entorno

Cada acción del entorno devuelve un código y, en caso de fallo,
añade un percept `error(Type, Data)` al agente. Los robots lo
detectan en `try_move`:

```jason
if (error(blocked_by_agent, _)) {
    !handle_block(NX, NY, TX, TY, Mode)
} else {
    !navigate_to(TX, TY, Mode)
}
```

### 8.2 Mecanismos de recuperación implementados

| Situación                         | Mecanismo                                                |
|-----------------------------------|----------------------------------------------------------|
| Bloqueo por otro robot            | `handle_block` + escape perpendicular                    |
| Drop falló (`shelf_full`)         | `release_shelf` + blacklist + reintento con alternativa  |
| Reintento sin alternativas        | `force_exit_carried` (entrega directa + `force_exit_cycle`) |
| Robot pisa paquete                | Entorno destruye paquete + broadcast `container_destroyed` |
| Splash recibido por agentes       | Cada uno purga sus referencias localmente                |
| Reubicación durante navegación    | `verify_position` re-navega a la nueva posición          |
| Claim denegado                    | `process_next` sin perder estado                         |
| Deadline expira con paquete en mano | `reshelf_carried` re-almacena en shelf compatible      |
| Deadline expira antes de retrieve | `abort_exit_cleanup` deja el paquete donde estaba        |
| `query_location` timeout          | Devuelve `none` y `handle_container` aborta limpiamente  |
| Reserva huérfana al iniciar deadline | Purga local de `shelf_reservation` por grupo          |
| `try_move` falla por excepción    | Reintento defensivo + propaga si falla otra vez          |
| Mensaje de peer perdido (heavy↔heavy2) | Timeout 2 s + nos quedamos el paquete                |
| `recover_carrying`                | Libera reserva + lo entregamos en la salida (best-effort) |
| `finish_task` sin reserva ni pending_drop | Catch-all `guardado/2` legacy: registra `log_pkg` sin tocar `shelf_usage` (no inflar con ceros) |
| Drift de `shelf_usage` por mensaje peer perdido | Recompute desde `stored_at` + `shelf_usage_snapshot` periódico del supervisor a los robots |

### 8.3 Casos donde el sistema podría romperse

1. **Race condition generador ↔ robot** sigue siendo
   teóricamente posible: un robot inicia `step` hacia (5,0)
   exactamente cuando el generador crea `c_X` ahí. La mitigación
   actual (destrucción + broadcast) preserva la consistencia
   pero **destruye el paquete**, pérdida real.
2. **`pending_drop` huérfano**: si una intención muere entre
   `reserve_shelf` y `commit_shelf`/`release_shelf` sin pasar
   por `-!handle_container` (por ejemplo, agente terminado por
   error fatal), el `pending_drop` se queda. Hoy no se observa,
   pero el código no tiene un GC explícito.
3. **Mensajes peer-to-peer perdidos o desordenados**: Jason
   garantiza entrega pero no orden. Si un `shelf_commit` llega
   antes que el `shelf_reserve` correspondiente, el peer intenta
   actualizaciones inconsistentes localmente. Mitigado en dos
   capas: `update_usage_local` clampa a 0 (no negativos) y, sobre
   todo, el `shelf_usage_snapshot` autoritativo del supervisor
   reescribe `shelf_usage_local` en cada robot (cada 15 s y tras
   cada cambio de stored_at), corrigiendo el drift acumulado.
4. **`finish_task` catch-all** envía `guardado/2` legacy al
   scheduler. Antes inflaba `shelf_usage` con W=0,V=0. Ahora el
   scheduler la registra solo en `log_pkg` (sin `package_stored`):
   el paquete físico queda huérfano en la shelf real pero la
   contabilidad ya no se distorsiona — y si más tarde se
   retira, el `package_retrieved` solo borra el `stored_at`
   correspondiente (que tampoco existe), sin efecto.
5. **Help_offer con datos rancios**: si el peer ofrece un CId que
   ya no tiene (porque arrancó execute_exit en paralelo) y el
   solicitante acepta, el `help_take` cae al catch-all y manda
   `help_deny`. Limpio, pero gasta una ronda. Aceptable.
6. **Limit `max_consecutive_errors(999)`** está prácticamente
   desactivado y `.stopMAS` comentado. Si algo se descontrola,
   el sistema sigue acumulando errores en lugar de pararse.

### 8.4 Logging de eventos

`log_event(Type, Data)` deja constancia en `eventlog.txt` de los
hitos relevantes para auditoría posterior:

- `output_phase_started`, `deadline_started`, `deadline_ended`.
- `container_delivered` (cada `drop_at_exit` exitoso).
- `no_space_detected`.
- `deadline_missed` (uno por contenedor pendiente al expirar).

---

## 9. Problemas detectados y mejoras propuestas

### 9.1 Código frágil o dudoso

1. **`Container.setAssignedShelf` con efecto colateral oculto**
   en (`x = -1, y = -1`). Si `setAssignedShelf(null)` (lo hace
   `retrieveFromShelf`), el contenedor "olvida" su posición.
   Funciona porque tras retrieve el robot lo lleva en la mano,
   pero no es robusto a refactors.
2. **Captura genérica `catch(Exception e) { e.printStackTrace(); }`**
   en muchas acciones de `WarehouseModel`. Oculta errores reales.
3. **Triple duplicación de topología** (Java, scheduler, work).
   Cualquier cambio en posiciones/capacidades hay que sincronizar
   en 3 sitios.
4. **`pending_drop` y `my_stored` desincronizables**: dependen de
   que la cadena reserve→commit no se rompa. El catch-all de
   `finish_task` lo intenta cubrir (firma `guardado/2` legacy).
5. **`finish_task` catch-all** ya no genera `package_stored` falsos
   con W=0/V=0; solo registra `log_pkg`. El paquete físico
   quedaría huérfano (sin `my_stored` y sin `stored_at`) pero la
   contabilidad de ocupación se mantiene íntegra.
6. **`escacharPaquete` solo gestiona splash de paquetes**
   sin recoger; un paquete recogido nunca cae al grid (asumido,
   no verificado).
7. **`pendiente.txt`** del propio repo enumera más casos: pisado
   de paquetes recién generados, pérdida de intención ante error
   `unknown` (ya mitigado), pathfinding mejorable.

### 9.2 Comportamientos inesperados o poco claros

1. **`container_available` se anuncia a los 4 robots aunque solo
   uno lo procese**. Tras introducir `faster_capable`, la
   partición es disjunta: solo el robot más rápido capaz lo
   encola, los demás abolishen el percept en el plan catch-all.
   Sigue habiendo "ruido de red" (4 mensajes por paquete) pero
   ya no hay colas duplicadas.
2. **El supervisor NO valida que `package_stored` corresponda a
   un `package_arrived`**: si el scheduler le envía un `Shelf`
   desconocido entra en el `pkg_stored_unknown` y solo incrementa
   total_stored sin tocar `stored_at`. Resultado: esos paquetes
   serán **invisibles para list_stored** y nunca saldrán por el
   ciclo de salida. Como `shelf_usage` ahora se deriva de
   `stored_at` (recompute), tampoco aparecen en la ocupación.
3. **El `total_errors(_)` percept del entorno se reemplaza en cada
   error**, así que el supervisor solo ve la cuenta acumulada del
   último tipo, no un histórico ordenado. La métrica es aproximada.
4. **El `help_request` se hace siempre con `MaxW`**, no
   `MaxW - peso_actual_carrying`. Ofrece paquetes que el peer
   "podría" cargar si estuviera vacío, pero el peer está vacío
   cuando consulta (post-execute), así que no es problema.

### 9.3 Mejoras técnicas sugeridas

1. **Centralizar la topología** en un único fichero de hechos
   compartido (Jason `include`) o derivarla del entorno vía un
   percept `topology(...)` al arranque.
2. **Cambiar pathfinding greedy por A***: el comentario en
   `Robot.java` lo anuncia ("Se viene A* chato"). Resolvería
   bloqueos en pasillos complejos sin dependencia del orden de
   shelves.
3. **Reemplazar `pending_announce` por una verdadera cola
   tipada** para evitar posibles duplicados.
4. **Detectar y reintentar mensajes peer perdidos** con un
   pequeño protocolo de ack para `shelf_commit`. Hoy se asume
   entrega.
5. **Reducir el "broadcast a 4" cuando solo 1 robot encajará**:
   un canal pre-filtrado por categoría (light/medium/heavy)
   evitaría las colas espúreas de robots que no van a procesar
   el paquete.
6. **Métricas separadas de `splash` vs `blocked_by_agent`**.
   Hoy todo cuenta como `total_errors` agregado.
7. **Reactivar `.stopMAS`** y bajar `max_consecutive_errors` a
   un valor realista para entrega final.
8. **Test automatizado mínimo** para escenarios estresantes (4
   urgentes seguidos, 70 % cruzado, dos robots compitiendo por
   el mismo claim). Hoy la validación es 100 % manual.
9. **GUI**: la consola se trunca a 500 líneas pero **no avisa**.
   Sería útil un indicador de "log truncado".

---

## 10. Apéndice — diccionario rápido de creencias clave

### Scheduler
- `package_info(CId, W, V, Type)` — caché por contenedor.
- `unstorable_pending(Group, [CIds])` — pendientes por grupo.
- `pending_announce(CId, W, H, Wt, Ty)` — caídos durante bloqueo.
- `pending_exit(CId, Loc, W, V, Type, Kind)` — exit_item activo.
- `claimed(CId)` — alguien ya reclamó.
- `exit_cycle_active`, `trigger_group(G)`, `blocked_group(G)`.
- `active_deadline(short|long)`, `deadline_shipped_count(K, N)`.
- `pending_queue([Groups])` — FIFO de triggers durante un ciclo.

### Supervisor
- `shelf_usage(S, W, V)` — derivada de `stored_at` por
  `recompute_shelf_usage`. NO se mantiene con +/- por evento.
- `shelf_capacity(S, MaxW, MaxV)`.
- `stored_at(CId, S, Type, W, V)` — quién almacena qué (única
  fuente de verdad del supervisor).
- `at_warehouse(CId, Type, W, V)` — ha entrado, no ha salido.
- `blocked_group_notified(G)` — ya avisé a scheduler.
- `snapshot_period_ms(P)` — periodo del broadcast autoritativo de
  `shelf_usage_snapshot` a los robots (15000 ms).
- `total_received(N)`, `total_stored(N)`, `deadline_violations(N)`.

### Robot
- `state(idle|going_idle|busy)`.
- `container_queue([pkg(...)])`.
- `shelf_usage_local(S, W, V)` — depósitos confirmados; se
  reescribe íntegro al recibir `shelf_usage_snapshot` del
  supervisor.
- `shelf_reservation(S, Owner, W, V, CId)` — reservas
  peer-to-peer, no se tocan al aplicar el snapshot.
- `pending_drop(CId, S, W, V)` — en vuelo entre reserve y commit.
- `my_stored(CId, S, W, V)` — paquetes míos en estanterías.
- `delegated_stored(CId, S, W, V)` — recibidos por help_take.
- `exit_item(CId, Loc, W, V, Type, Kind)`, `pending_claim(CId, Loc, Type)`.
- `exit_in_progress(CId)`, `carrying_exit(CId, Type, S, W, V)`.
- `carrying_fragile`, `prev_pos`, `visited(X,Y)`, `block_streak(N)`.

---

> **Notas finales para el lector**: este documento describe el
> sistema tal y como está implementado en la rama `salida` con
> los archivos `.asl` y Java leídos. Para ampliar a memoria
> profesional se recomienda añadir: (a) capturas de la GUI con
> ejemplos de cada caso del §6, (b) gráficos de tiempos
> (timeline UML de un deadline), (c) tabla de cumplimiento del
> enunciado punto por punto, (d) métricas reales tras N corridas
> del sistema con el `eventlog.txt` como evidencia.
