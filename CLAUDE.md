# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Comandos

Todo se ejecuta desde el subdirectorio `warehouse/` (no desde la raíz):

```bash
cd warehouse
./gradlew run            # compila y arranca el MAS (Java 21 + Jason 3.3.0)
./gradlew build          # solo compila
./gradlew clean          # limpia bin/ y default.mas2j
jason warehouse.mas2j    # alternativa si jason está en PATH
```

No hay suite de tests automatizada — la validación es manual observando la GUI Swing (`WarehouseView`) y los `.print` de los agentes en la consola Jason.

Logging: se controla en [warehouse/logging.properties](warehouse/logging.properties). Por defecto INFO; subir a FINE para ver el detalle interno de Jason.

## Arquitectura

Sistema multiagente Jason (BDI) sobre un entorno Java. El MAS se declara en [warehouse/warehouse.mas2j](warehouse/warehouse.mas2j) e instancia 7 agentes:

- **4 robots** (`robot_light`, `robot_medium`, `robot_heavy`, `robot_heavy2`) con capacidades distintas (peso/tamaño/velocidad) y prioridad de paso definida en cada `.asl`.
- **`scheduler`** — punto central de información de contenedores y orquestador del ciclo de salida por deadlines. NO asigna shelves a robots ni paquetes a robots concretos.
- **`supervisor`** — métricas, ocupación real de shelves, y dispara `no_space(Type)` al alcanzar el 70% de saturación por grupo.
- **`transport`** — agente externo que simula el camión que recoge en cada deadline.

### División entorno ↔ agentes (principio clave)

El entorno Java [warehouse/src/env/warehouse/](warehouse/src/env/warehouse/) (`WarehouseArtifact` + `WarehouseModel`) expone solo **estado + acciones "tontas"**: `step`, `pickup`, `drop_at`, `drop_at_exit`, `retrieve`, `relocate_container`, `see`, `get_container_info`, `get_shelf_adjacent`, `block_generation`/`unblock_generation`, etc. Toda la lógica de coordinación, prioridades y razonamiento vive en los `.asl`. **No mover lógica al entorno**.

### Lógica común de robots: `work.asl` + `mov.asl`

Cada `robot_*.asl` es minimalista (creencias propias: `idlezone`, `max_weight`, `priority`, `robot_shelf_priority`, `can_i_manage`) y hace `include` de:

- [warehouse/src/agt/work.asl](warehouse/src/agt/work.asl) — gestión de cola, selección local de shelf con reservas peer-to-peer, ciclo de salida con `claim` al scheduler.
- [warehouse/src/agt/mov.asl](warehouse/src/agt/mov.asl) — pathfinding greedy con tabú (`prev_pos`, `visited`), escape perpendicular, resolución de bloqueos por prioridad, navegación a shelf vía celdas adyacentes.

### Protocolo de almacenamiento (peer-to-peer)

El scheduler hace `broadcast tell container_available(...)` y NO asigna shelf. Cada robot decide localmente:

1. `can_i_manage(W, H, Weight)` filtra por capacidad.
2. `choose_shelf_local` consulta `shelf_usage_local` + `shelf_reservation` (estado replicado en cada robot vía mensajes `shelf_reserve`/`shelf_commit`/`shelf_release`/`shelf_retrieved`).
3. Si nada cabe → `tell unstorable(CId, Type)` al scheduler. Si cabe → reserva, broadcast a peers, pickup, drop, commit.

Heavy y heavy2 son **simétricos**: ambos reciben `container_available` y ejecutan `decide_heavy_peer` (regla determinista por `my_stored` → cola → estado → nombre) para que solo uno acabe encolando.

### Ciclo de salida por deadlines

Disparado por `no_space(Type)` del supervisor o por umbral de unstorable acumulados. El scheduler:

1. Bloquea generación de todos los tipos (`block_generation` en el entorno).
2. **Deadline corto** [T0, T0+ΔT]: solo URGENTES.
3. **Deadline largo** [T0+ΔT, T0+3ΔT]: solo NO-URGENTES (`standard` + `fragile`).

ΔT se define en `delta_t/1` en [warehouse/src/agt/scheduler.asl](warehouse/src/agt/scheduler.asl). Para cada deadline publica `exit_item(CId, Loc, W, V, Type, Kind)` a los 4 robots; cada uno elige el más cercano que pueda cargar y pide `claim_exit` al scheduler antes de retirar (lock atómico). Al cerrar, abolish de los `exit_item` no consumidos y desbloqueo.

`type_group/2` agrupa tipos para el ciclo: `standard` y `fragile` comparten shelves → grupo `normal`; `urgent` va aparte.

### Topología fija (memorizar)

Coordenadas hardcodeadas en `WarehouseModel.initializeGrid` y replicadas como hechos en scheduler/supervisor/work:

- Zona salida: `x ∈ [0..2], y ∈ [0..1]` (celdas `exit_cell`)
- Clasificación: `x ∈ [3..4], y ∈ [0..1]`
- Entrada: `x ∈ [5..7], y ∈ [0..1]`
- Shelves: 9 shelves en filas `y=2,3` / `y=6,7` / `y=10,11,12`. Capacidades en `shelf_capacity/3`.
- Urgentes: shelves 1, 5, 8. Regulares: 2, 3, 4, 6, 7, 9.

## Convenciones del proyecto

- **Percepts = átomos sin comillas.** Los IDs (`container_X`, `shelf_N`) deben llegar al `.asl` como átomos, no strings, o se rompe la unificación. Ver `executePickup`/`executeDropAt` que hacen `.replace("\"", "")`.
- **Prioridad de eje en `mov.asl/next_step`: SIEMPRE Y primero**, X solo cuando ya estamos alineados en Y. La distribución horizontal de shelves hace que el greedy "mayor delta" se atasque en pasillos.
- **No añadir lógica de coordinación al entorno Java**. Si necesitas bloquear o consensuar, hazlo con mensajes entre agentes (`tell`/`achieve`/`broadcast`).
- **Estado de shelves duplicado intencionalmente**: el supervisor lleva `shelf_usage` real (autoritativa), cada robot lleva `shelf_usage_local` + `shelf_reservation` para decidir sin round-trip. Mantenerlas sincronizadas vía los mensajes peer.
- Idioma: comentarios y `.print` en español. Mantener el estilo.

## Documentación de referencia

Documentación del enunciado en [warehouse/initial_documentation/](warehouse/initial_documentation/) (versiones `_ES` y `_EN`). El proyecto se entrega en [warehouse/doc/](warehouse/doc/) con `memoria.pdf` + copia de `src/agt/`.
