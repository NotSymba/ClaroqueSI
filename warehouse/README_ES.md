# 📦 Warehouse Management System

**Sistema Multiagente para Gestión Logística de Almacén Automatizado**

Universidad de Vigo - Sistemas Inteligentes - Curso 2025-2026

> 🌐 **[English version available](README_EN.md)** / **Versión en inglés disponible**

---

## 🚀 Inicio Rápido

```bash
# Ejecutar el proyecto
jason warehouse.mas2j
```

**Requisitos:** Java 21+ y Jason 3.3.0

---

## 📁 Estructura del Proyecto

```
warehouse/
├── README.md                  # Este archivo (guía rápida)
├── warehouse.mas2j            # Configuración del sistema multiagente
│
├── src/                       # CÓDIGO FUENTE
│   ├── agt/                   # ⚠️ AGENTES - IMPLEMENTAR AQUÍ
│   │   ├── robot_light.asl    # Robot ligero (10kg, 1×1)
│   │   ├── robot_medium.asl   # Robot medio (30kg, 1×2)
│   │   ├── robot_heavy.asl    # Robot pesado (100kg, 2×3)
│   │   ├── scheduler.asl      # Planificador de tareas
│   │   └── supervisor.asl     # Monitor del sistema
│   │
│   └── env/warehouse/         # ENTORNO - PROPORCIONADO
│       ├── WarehouseArtifact.java
│       ├── WarehouseView.java
│       ├── Container.java
│       ├── Shelf.java
│       ├── Robot.java
│       └── CellType.java
│
├── initial_documentation/     # 📚 DOCUMENTACIÓN PROPORCIONADA
│   ├── README_ES.md / README_EN.md              # Guía completa del proyecto
│   ├── QUICKSTART_ES.md / QUICKSTART_EN.md      # Tutorial de inicio (5 min + 30 min)
│   ├── DEBUGGING_ES.md / DEBUGGING_EN.md        # Solución de problemas comunes
│   ├── PROJECT_SUMMARY_ES.md / PROJECT_SUMMARY_EN.md  # Resumen del estado del proyecto
│   ├── BUILD_AND_RUN_ES.md / BUILD_AND_RUN_EN.md      # Instrucciones de compilación
│   └── PRESENTACION_ES.md / PRESENTACION_EN.md        # Presentación para alumnos
│
├── doc/                       # 📦 ENTREGA DEL ALUMNADO
│   └── README_ES.md / README_EN.md              # Instrucciones de entrega
│
├── build.gradle               # Configuración de Gradle
└── logging.properties         # Configuración de logs
```

---

## 🎯 ¿Qué Implementar?

### Archivos a Completar (en `src/agt/`)

1. **`robot_light.asl`** - Lógica del robot ligero
2. **`robot_medium.asl`** - Lógica del robot medio
3. **`robot_heavy.asl`** - Lógica del robot pesado
4. **`scheduler.asl`** - Coordinación y asignación de tareas
5. **`supervisor.asl`** - Monitorización y gestión de errores

### Archivos Proporcionados

- Todo el contenido de `src/env/warehouse/` (entorno Java)
- Configuración del sistema (`warehouse.mas2j`)

---

## 📚 Documentación

> **Nota:** Toda la documentación está disponible en **español (_ES)** e **inglés (_EN)**.

### Para Empezar:

1. **[initial_documentation/QUICKSTART_ES.md](initial_documentation/QUICKSTART_ES.md)** ([EN](initial_documentation/QUICKSTART_EN.md)) - Empieza aquí (tutorial paso a paso)
2. **[initial_documentation/README_ES.md](initial_documentation/README_ES.md)** ([EN](initial_documentation/README_EN.md)) - Documentación completa del proyecto
3. **[initial_documentation/PRESENTACION_ES.md](initial_documentation/PRESENTACION_ES.md)** ([EN](initial_documentation/PRESENTACION_EN.md)) - Presentación del proyecto

### Durante el Desarrollo:

- **[initial_documentation/DEBUGGING_ES.md](initial_documentation/DEBUGGING_ES.md)** ([EN](initial_documentation/DEBUGGING_EN.md)) - Problemas comunes y soluciones
- **[initial_documentation/PROJECT_SUMMARY_ES.md](initial_documentation/PROJECT_SUMMARY_ES.md)** ([EN](initial_documentation/PROJECT_SUMMARY_EN.md)) - Estado del proyecto
- **[initial_documentation/BUILD_AND_RUN_ES.md](initial_documentation/BUILD_AND_RUN_ES.md)** ([EN](initial_documentation/BUILD_AND_RUN_EN.md)) - Compilación y ejecución

### Recursos Externos:

- [Libro Jason](https://jason-lang.github.io/book/) (disponible en Moovi)
- [Documentación oficial Jason](https://jason-lang.github.io)
- [GitHub Jason](https://github.com/jason-lang/jason)

---

## 📦 Entrega del Proyecto

### Ubicación de Entrega

Coloca tu documentación y solución en la carpeta **`doc/`**:

```
doc/
├── docs/ 
│   └── memoria.pdf           # Memoria técnica del proyecto
├── src/                      # Copia de tu código implementado
│   └── agt/
│       ├── robot_light.asl
│       ├── robot_medium.asl
│       ├── robot_heavy.asl
│       ├── scheduler.asl
│       └── supervisor.asl
└── README.md                 # Instrucciones específicas de tu solución
```

### Contenido de la Memoria debe incluir


>Se espera que la memoria tenga la calidad técnica y redacción adecuada, con diagramas claros y explicaciones detalladas. Deberá explicar las decisiones de diseño, la lógica de los agentes, la interacción entre ellos y cómo se han abordado los objetivos del proyecto. Además, debe incluir dificultades encontradas y cómo se han solucionado, así como referencias y posibles mejoras futuras si el tiempo lo permite.

> La memoria debe ser clara, concisa y bien estructurada, facilitando la comprensión del proyecto a cualquier lector.

> No se espera que sea un documento extenso, pero sí completo y bien estructurado.
### Formato de Entrega Final

Comprimir en un archivo **ZIP** con el siguiente contenido:

- Carpeta completa `warehouse/` con vuestro código
- Archivo `memoria.pdf` en `doc/`

**Nombre del archivo:** `warehouse_grupoXX.zip`


---

## Trabajo en Grupo

- Grupos de hasta **7 estudiantes**
- Se recomienda usar Git/GitHub para colaborar
- Todos los miembros deben participar en la defensa oral
- Entregar en plazo (ver Moovi para fechas)

---

## 📄 Licencia

Material docente de la **Universidad de Vigo** para la asignatura de **Sistemas Inteligentes**. 


