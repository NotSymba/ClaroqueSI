# 📦 Proyecto Warehouse - Resumen Completo

## ✅ Estado del Proyecto: LISTO PARA ENTREGAR AL ALUMNADO

---

## 📊 Resumen Ejecutivo

**Proyecto:** Sistema Multiagente para Gestión Logística de Almacén Automatizado  
**Plataforma:** Jason/JaCaMo 3.3.0  
**Curso:** Sistemas Inteligentes 2025-2026  
**Universidad:** Universidade de Vigo

---

## 📁 Estructura Completa del Proyecto

```
warehouse/
├── warehouse.mas2j                    # Configuración principal del MAS
├── logging.properties                 # Configuración de logs
├── .gitignore                         # Control de versiones
│
├── initial_documentation/
│   ├── README_ES.md / README_EN.md         # Documentación completa
│   ├── QUICKSTART_ES.md / QUICKSTART_EN.md # Guía de inicio rápido
│   └── DEBUGGING_ES.md / DEBUGGING_EN.md   # Guía de debugging y troubleshooting
│
├── src/
│   ├── agt/                          # AGENTES (para implementar por alumnado)
│   │   ├── robot_light.asl           # Robot ligero (plantilla + guías)
│   │   ├── robot_medium.asl          # Robot medio (plantilla + guías)
│   │   ├── robot_heavy.asl           # Robot pesado (plantilla + guías)
│   │   ├── scheduler.asl             # Scheduler (plantilla + guías)
│   │   └── supervisor.asl            # Supervisor (plantilla + guías)
│   │
│   └── env/warehouse/                # ENTORNO (proporcionado, cerrado)
│       ├── WarehouseArtifact.java    # Artefacto principal
│       ├── WarehouseView.java        # GUI visual 2D 
│       ├── Container.java            # Modelo de contenedor
│       ├── Shelf.java                # Modelo de estantería
│       ├── Robot.java                # Modelo de robot
│       └── CellType.java             # Enum de tipos de celda
```


---

## Componentes

### ✅ Entorno Completo

#### WarehouseArtifact.java
- ✅ Gestión completa del grid 20×15
- ✅ Generador automático de contenedores (5-10 segundos)
- ✅ **Thread-safety corregido:**
  - `ConcurrentLinkedQueue` para cola de contenedores
  - `ConcurrentHashMap` para almacenamiento concurrent-safe
  - `ExecutorService` para generador de contenedores con shutdown apropiado
  - Método `stop()` implementado para limpieza de recursos
- ✅ 7 acciones implementadas:
  - `move_to(X,Y)` - Movimiento de robots
  - `pickup(ContainerId)` - Recoger contenedor
  - `drop_at(ShelfId)` - Depositar en estantería
  - `request_task()` - Solicitar tarea
  - `get_container_info(CId)` - Información de contenedor
  - `get_free_shelf(CId)` - Buscar estantería libre
  - `scan_surroundings()` - Escanear alrededores
- ✅ 8 percepciones implementadas
- ✅ 6 tipos de errores implementados
- ✅ Sistema de métricas y estadísticas
- ✅ Inicialización de 3 robots
- ✅ Inicialización de múltiples estanterías
- ✅ Validación completa de acciones
- ✅ Detección de colisiones
- ✅ Gestión de zona de entrada, clasificación y almacenamiento
- ✅ Integración con consola GUI para logging de actividades

#### WarehouseView.java (GUI Visual)
- ✅ Renderizado 2D del almacén (40px por celda)
- ✅ Visualización de grid con colores por zona
- ✅ Robots como círculos coloreados (light=verde, medium=azul, heavy=magenta)
- ✅ Contenedores con colores por tipo (normal, frágil, urgente)
- ✅ Estanterías con indicador de ocupación
- ✅ **Panel de información lateral expandido (450px de ancho):**
  - Estadísticas generales
  - Estado de robots en tiempo real
  - Estado de estanterías
  - Text areas más grandes para mejor visibilidad
- ✅ **Consola de actividad en panel inferior (180px de altura):**
  - Log en tiempo real con timestamps
  - Fondo negro con texto verde (estilo terminal)
  - Auto-scroll hacia últimos mensajes
  - Límite de 500 líneas (auto-limpieza)
  - Muestra movimientos, recogidas, almacenamientos, errores
- ✅ Actualización automática cada segundo
- ✅ Interfaz responsive y clara
- ✅ Método `logMessage()` para integración con WarehouseArtifact

#### Modelos de Datos
- ✅ **Container**: Propiedades completas (tamaño, peso, tipo)
- ✅ **Shelf**: Capacidad, ocupación, validación
- ✅ **Robot**: Capacidades, estado, navegación
- ✅ **CellType**: Enum de tipos de celda

### ✅ Plantillas de Agentes (Para Alumnado)

Cada archivo de agente incluye:
- ✅ Comentarios extensivos explicando responsabilidades
- ✅ Explicación de percepciones y acciones

#### robot_light.asl
- Plantilla para robot ligero (10kg, 1×1, velocidad alta)

#### robot_medium.asl
- Plantilla para robot medio (30kg, 1×2, velocidad media)

#### robot_heavy.asl
- Plantilla para robot pesado (100kg, 2×3, velocidad baja)
- Énfasis en eficiencia (recurso escaso)
- Estrategias de optimización

#### scheduler.asl
- Plantilla extensiva con múltiples secciones
- Clasificación de contenedores
- Asignación de tareas con estrategias
- Monitorización del sistema
- Reglas de negocio y optimización
- Comunicación con robots

#### supervisor.asl
- Monitorización continua
- Detección de anomalías
- Análisis de errores
- Generación de reportes
- Métricas de rendimiento

### ✅ Documentación Completa

#### README_ES.md / README_EN.md
- Descripción general del proyecto
- Objetivos y tareas del alumnado
- Estructura del proyecto

#### QUICKSTART_ES.md / QUICKSTART_EN.md
- Inicio en rápido
- Primera implementación

#### DEBUGGING_ES.md / DEBUGGING_EN.md
- Técnicas de debugging en Jason
- 8+ problemas comunes con soluciones
- Checklist completo de debugging
- Herramientas útiles
- Comandos de AgentSpeak
- Consejos


---

## Requisitos del Sistema

- **Java:** JDK 21 o superior
- **Jason:** 3.3.0
- **SO:** Linux, macOS, Windows
- **RAM:** 2GB mínimo
- **Pantalla:** 1920×1080 recomendado (GUI)

