# Sistema Multiagente para Gestión Logística de Almacén Automatizado

**Universidad de Vigo - Sistemas Inteligentes**  
**Curso 2025-2026**


## Descripción General

Este proyecto implementa un **sistema multiagente** para la gestión inteligente de un almacén logístico automatizado usando **Jason/JaCaMo**. El sistema coordina robots reponedores heterogéneos para transportar contenedores desde zonas de entrada hasta estanterías de almacenamiento.


## Interfaz Gráfica (GUI)

El sistema incluye una **visualización en tiempo real** dividida en tres áreas principales:


### 🎨 Mapa del Almacén (Centro)

**Grid de 20×15 celdas** con zonas funcionales diferenciadas por colores:

| Color | Zona | Ubicación | Función |
|-------|------|-----------|---------|
| 🟢 **Verde claro** | Entrada | Esquina superior izquierda (0-2, 0-1) | Recepción de contenedores |
| 🟡 **Amarillo claro** | Clasificación | Superior (3-6, 0-1) | Procesamiento de contenedores |
| ⬜ **Blanco/Gris** | Navegación | Resto del grid | Espacios transitables |
| 🟪 **Gris azulado** | Estanterías | Áreas específicas | Almacenamiento |


### 🤖 Robots

**Representados como círculos coloreados:**

- 🟢 **Verde**: Robot ligero (10kg, 1×1) - Velocidad alta
- 🔵 **Azul**: Robot medio (30kg, 1×2) - Velocidad media  
- 🟣 **Magenta**: Robot pesado (100kg, 2×3) - Velocidad baja

Cuando un robot **transporta un contenedor**, se muestra un pequeño cuadrado amarillo en su esquina superior derecha.


### 📦 Contenedores

**Representados como cuadrados pequeños:**

- 🔵 **Azul**: Contenedores estándar (70%)
- 🔴 **Rojo claro**: Contenedores frágiles (15%)
- 🟠 **Naranja**: Contenedores urgentes (15%)


### 📚 Estanterías

**Rectángulos con código de colores según ocupación:**

- 🟢 **Verde**: < 50% ocupado (disponible)
- 🟡 **Amarillo**: 50-80% ocupado (parcialmente lleno)
- 🔴 **Rojo**: > 80% ocupado (casi lleno)

Cada estantería muestra su **ID** y **porcentaje de ocupación**.


### 📊 Panel de Información (Derecha)

**Tres secciones actualizadas en tiempo real:**

1. **Statistics**: Tiempo transcurrido, contenedores procesados, pendientes, errores
2. **Robots**: Posición, estado (ocupado/libre), carga actual
3. **Shelves**: Ubicación, ocupación, peso, volumen, items almacenados


### 📝 Consola de Actividad (Inferior)

**Log en tiempo real con timestamps** mostrando:

- ➡️ Movimientos de robots
- 📦 Recogidas de contenedores  
- ✅ Almacenamientos exitosos
- 🆕 Generación de nuevos contenedores
- ❌ Errores y alertas

**Características:**
- Fondo negro con texto verde (estilo terminal)
- Auto-scroll hacia últimos mensajes
- Límite de 500 líneas (auto-limpieza)


## Objetivos del Proyecto

El alumnado debe implementar la lógica de los agentes para:

1. ✅ Gestionar la recepción y clasificación de contenedores
2. ✅ Asignar tareas a robots según capacidades
3. ✅ Planificar rutas de navegación
4. ✅ Evitar colisiones entre robots
5. ✅ Manejar errores del entorno
6. ✅ Optimizar eficiencia del almacén
7. ✅ Monitorizar el sistema y generar métricas


## Estructura del Proyecto

```
warehouse/
├── warehouse.mas2j              # Configuración del sistema multiagente
├── src/
│   ├── agt/                     # Agentes (A IMPLEMENTAR)
│   │   ├── robot_light.asl      # Robot ligero
│   │   ├── robot_medium.asl     # Robot medio
│   │   ├── robot_heavy.asl      # Robot pesado
│   │   ├── scheduler.asl        # Planificador de tareas
│   │   └── supervisor.asl       # Monitor y gestor de errores
│   └── env/warehouse/           # Entorno (PROPORCIONADO)
│       ├── WarehouseArtifact.java
│       ├── WarehouseView.java
│       ├── Container.java
│       ├── Shelf.java
│       ├── Robot.java
│       └── CellType.java
└── README.md                    
```


## Componentes del Sistema
- Robots Reponedores
- Agentes de Control
- Contenedores
- Estanterías 



### Robots Reponedores

| Robot        | Peso Máx | Tamaño Máx | Velocidad | Archivo            |
|--------------|----------|------------|-----------|---------------------|
| `robot_light`  | 10 kg    | 1×1        | Alta (3)  | `robot_light.asl`   |
| `robot_medium` | 30 kg    | 1×2        | Media (2) | `robot_medium.asl`  |
| `robot_heavy`  | 100 kg   | 2×3        | Baja (1)  | `robot_heavy.asl`   |


### Agentes de Control

- **Scheduler** (`scheduler.asl`): Coordina la asignación de tareas
- **Supervisor** (`supervisor.asl`): Monitoriza el sistema y gestiona errores


### Contenedores

- **Tamaños**: 1×1, 1×2, 2×2, 2×3
- **Pesos**: 5 a 100 kg
- **Tipos**: `standard` (70%), `fragile` (15%), `urgent` (15%)
- **Generación**: automática cada 5-10 segundos


### Estanterías

- Diferentes capacidades de peso y volumen
- Limitadas por espacio disponible
- Distribuidas en el área de almacenamiento


## API del Entorno (WarehouseArtifact)

### Acciones Disponibles

```asl
move_to(X, Y)              // Mover robot a posición (X,Y)
pickup(ContainerId)        // Recoger contenedor
drop_at(ShelfId)           // Depositar en estantería
request_task()             // Solicitar nueva tarea
get_container_info(CId)    // Obtener info de contenedor
get_free_shelf(CId)        // Buscar estantería libre
scan_surroundings()        // Escanear alrededores
```


### Percepciones Recibidas

```asl
+robot_at(X,Y)                     // Posición actualizada
+task(ContainerId, ShelfId)        // Nueva tarea asignada
+picked(ContainerId)               // Contenedor recogido
+stored(ContainerId, ShelfId)      // Contenedor almacenado
+cell(X,Y,Type)                    // Información de celda
+blocked(X,Y)                      // Celda bloqueada
+error(Type, Data)                 // Error ocurrido
+new_container(ContainerId)        // Nuevo contenedor generado
+container_info(CId,W,H,Weight,Type) // Info de contenedor
```

### Tipos de Errores

- `container_too_heavy`: Robot no puede cargar por peso
- `container_too_big`: Robot no puede cargar por tamaño
- `shelf_full`: Estantería sin espacio
- `illegal_move`: Movimiento fuera de límites
- `conflict`: Colisión con otro robot
- `route_blocked`: Ruta bloqueada


## Ejecución del Proyecto

### Requisitos Previos

- **Java JDK** 21 o superior
- **Jason** 3.3.0 (instalado en `/home/XXXX/jason-3.3.0/`)

### Compilar y Ejecutar

```bash
# Navegar al directorio del proyecto
cd /home/XXXX/jason-3.3.0/projects/warehouse

# Ejecutar con Jason
jason warehouse.mas2j
```


## Pruebas y Validación

### Casos de Prueba

1. **Prueba Básica**: Un robot, un contenedor
2. **Prueba Múltiple**: Tres robots, múltiples contenedores
3. **Prueba de Capacidad**: Contenedores que solo robot pesado puede manejar
4. **Prueba de Errores**: Estantería llena, contenedor muy pesado
5. **Prueba de Colisión**: Dos robots intentan moverse al mismo lugar
6. **Prueba de Carga**: Generación rápida de contenedores


### Métricas de Éxito

- ✅ **Documentación**: Informe completo y claro
- ✅ **Funcionalidad**: Todos los contenedores son almacenados correctamente
- ✅ **Eficiencia**: Tiempo promedio < 30 segundos por contenedor
- ✅ **Robustez**: Tasa de errores < 10%
- ✅ **Coordinación**: Sin colisiones ni deadlocks
- ✅ **Utilización**: Robots ociosos < 30% del tiempo



## Visualización

El sistema incluye una **interfaz gráfica 2D** que muestra:

- **Grid del almacén** con zonas coloreadas
- **Robots** como círculos coloreados (verde=light, azul=medium, magenta=heavy)
- **Contenedores** como cuadrados (azul=normal, rojo=frágil, naranja=urgente)
- **Estanterías** con indicador de ocupación (verde < 50%, amarillo 50-80%, rojo > 80%)
- **Panel de información** con estadísticas en tiempo real


## Criterios de Evaluación

| Aspecto                          | Peso | Descripción                                    |
|----------------------------------|------|------------------------------------------------|
| **Funcionalidad**                | 30%  | Sistema completo y operativo                   |
| **Diseño Multiagente**           | 20%  | Buena arquitectura y distribución de roles     |
| **Representación Conocimiento**  | 15%  | Uso correcto de creencias, reglas y planes     |
| **Gestión de Errores**           | 15%  | Manejo robusto de situaciones anómalas         |
| **Eficiencia**                   | 10%  | Optimización de recursos y tiempos             |
| **Código y Documentación**       | 10%  | Código limpio, comentado y bien estructurado   |


## Consejos y Buenas Prácticas

### Desarrollo

- 🎯 **Incremental**: Implementar funcionalidad básica primero, luego optimizar
- 🧪 **Probar frecuentemente**: Ejecutar después de cada cambio importante
- 📝 **Comentar**: Explicar lógica compleja en comentarios
- 🔍 **Debug con prints**: Usar `.print()` liberalmente durante desarrollo


### Errores Comunes

- ❌ No verificar capacidad antes de asignar tarea
- ❌ No actualizar estado del robot tras acciones
- ❌ No manejar casos donde no hay robot disponible
- ❌ Olvidar marcar robot como libre tras completar tarea
- ❌ No considerar distancias en asignación de tareas


### Optimizaciones Avanzadas

- 🚀 Planificación de rutas A* o Dijkstra
- 🚀 Predicción de llegada de contenedores
- 🚀 Pre-asignación de tareas
- 🚀 Batching de contenedores similares
- 🚀 Aprendizaje de patrones de tráfico


## Recursos Adicionales

### Documentación Jason

- [Libro "Programming Multi-Agent Systems in AgentSpeak using Jason"](https://jason-lang.github.io/book/) Disponible en Moovi.
- [Documentación oficial de Jason](https://jason-lang.github.io)
- [Releases de Jason (jason-lang/jason) en GitHub](https://github.com/jason-lang/jason/releases)
- [Referencia de comandos CLI de Jason](https://jason-lang.github.io/doc/jason-cli/commands.html)


### Conceptos Clave

- **Creencias** (beliefs): Conocimiento del agente
- **Planes**: evento : contexto <- acciones
- **Percepciones**: Información del entorno
- **Acciones**: Modificación del entorno
- **Comunicación**: `.send()`, `.broadcast()`


## Resolución de Problemas

### El sistema no arranca

```bash
# Verificar Java
java -version

# Verificar JASON_HOME
echo $JASON_HOME

# Recompilar
cd /home/ivan/jason-3.3.0/projects/warehouse
jason warehouse.mas2j
```

### Los agentes no se comunican

- Verificar que los nombres de agentes en `.mas2j` coinciden
- Usar `[source(Agent)]` para identificar emisor
- Revisar sintaxis de `.send()`


### Errores de compilación Java

```bash
# Verificar que las clases están en el paquete correcto
# Todas las clases de entorno deben estar en: warehouse/
```

### La GUI no se muestra

- Verificar que no hay errores en el código Java
- Revisar consola en busca de excepciones
- Asegurar que `WarehouseView` se instancia correctamente


## Equipo y Entrega

### Trabajo en Grupo

- Grupos de hasta **7 estudiantes**
- Distribuir tareas.
- Reuniones periódicas para integración.
- Se recomienda el uso de herramientas para el control de versiones de código, como por ejemplo GitHub, GitLab o Bitbucket.


### Entregables

1. **Código fuente** completo
2. **Memoria del proyecto**:
   - Diseño del sistema multiagente
   - Decisiones de implementación
   - Representación del conocimiento
   - Análisis de resultados
   - Conclusiones y trabajo futuro
4. **Defensa oral** del proyecto. Todos los miembros del grupo deben participar.

### Warning

 :warning: Debe entregarse un único proyecto por grupo, con el código completo y la memoria en formato PDF. Todo debe ser comprimido en un fichero ZIP. 

:warning:  No se corregirán prácticas entregadas fuera de plazo, ni prácticas que no cumplan con el formato requerido.
 


## Soporte

Para dudas o problemas:

- **Foros de la asignatura**: moovi.uvigo.es
- **Email**: ivan.luis@uvigo.es


## Licencia

Este proyecto es material docente de la **Universidad de Vigo** para la asignatura de **Sistemas Inteligentes**. 


