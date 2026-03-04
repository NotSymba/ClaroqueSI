# Warehouse Management System - Jason Application

Multi-Agent System for Intelligent Warehouse Logistics Management

### Requirements

- Java 21 or higher
- Jason 3.3.0

### Option 1: Run with Jason (Recommended)

```bash
# From the project directory
/home/XXXX/jason-3.3.0/bin/jason warehouse.mas2j
```

### Option 2: Compile with Gradle

```bash
# Compile the project
./gradlew build

# Run the project
./gradlew run
```

## 📁 Project Structure

```
warehouse/
├── src/
│   ├── agt/               # Jason Agents (.asl)
│   │   ├── robot_light.asl
│   │   ├── robot_medium.asl
│   │   ├── robot_heavy.asl
│   │   ├── scheduler.asl
│   │   └── supervisor.asl
│   └── env/               # Java Environment
│       └── warehouse/
│           ├── WarehouseArtifact.java
│           ├── WarehouseView.java
│           ├── Robot.java
│           ├── Container.java
│           ├── Shelf.java
│           └── CellType.java
├── build.gradle           # Gradle configuration
├── settings.gradle        # Project configuration
└── warehouse.mas2j        # MAS configuration
```
