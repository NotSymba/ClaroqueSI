# Warehouse Management System - Jason Application

Sistema Multiagente para Gestión Logística Inteligente de un Almacén Automatizado

### Requisitos

- Java 21 o superior
- Jason 3.3.0

### Opción 1: Ejecutar con Jason (Recomendado)

```bash
# Desde el directorio del proyecto
/home/XXXX/jason-3.3.0/bin/jason warehouse.mas2j
```

### Opción 2: Compilar con Gradle

```bash
# Compilar el proyecto
./gradlew build

# Ejecutar el proyecto
./gradlew run
```

## 📁 Estructura del Proyecto

```
warehouse/
├── src/
│   ├── agt/               # Agentes Jason (.asl)
│   │   ├── robot_light.asl
│   │   ├── robot_medium.asl
│   │   ├── robot_heavy.asl
│   │   ├── scheduler.asl
│   │   └── supervisor.asl
│   └── env/               # Entorno Java
│       └── warehouse/
│           ├── WarehouseArtifact.java
│           ├── WarehouseView.java
│           ├── Robot.java
│           ├── Container.java
│           ├── Shelf.java
│           └── CellType.java
├── build.gradle           # Configuración de Gradle
├── settings.gradle        # Configuración del proyecto
└── warehouse.mas2j        # Configuración del MAS
```

