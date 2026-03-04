# 📦 Warehouse Management System

**Multi-Agent System for Automated Warehouse Logistics Management**

University of Vigo - Intelligent Systems - Course 2025-2026

> 🌐 **[Versión en español disponible](README.md)** / **Spanish version available**

---

## 🚀 Quick Start

```bash
# Run the project
jason warehouse.mas2j
```

**Requirements:** Java 21+ and Jason 3.3.0

---

## 📁 Project Structure

```
warehouse/
├── README.md                  # This file (quick guide)
├── warehouse.mas2j            # Multi-agent system configuration
│
├── src/                       # SOURCE CODE
│   ├── agt/                   # ⚠️ AGENTS - IMPLEMENT HERE
│   │   ├── robot_light.asl    # Light robot (10kg, 1×1)
│   │   ├── robot_medium.asl   # Medium robot (30kg, 1×2)
│   │   ├── robot_heavy.asl    # Heavy robot (100kg, 2×3)
│   │   ├── scheduler.asl      # Task scheduler
│   │   └── supervisor.asl     # System monitor
│   │
│   └── env/warehouse/         # ENVIRONMENT - PROVIDED
│       ├── WarehouseArtifact.java
│       ├── WarehouseView.java
│       ├── Container.java
│       ├── Shelf.java
│       ├── Robot.java
│       └── CellType.java
│
├── initial_documentation/     # 📚 PROVIDED DOCUMENTATION
│   ├── README_ES.md / README_EN.md              # Complete project guide
│   ├── QUICKSTART_ES.md / QUICKSTART_EN.md      # Getting started tutorial (5 min + 30 min)
│   ├── DEBUGGING_ES.md / DEBUGGING_EN.md        # Common problems solutions
│   ├── PROJECT_SUMMARY_ES.md / PROJECT_SUMMARY_EN.md  # Project status summary
│   ├── BUILD_AND_RUN_ES.md / BUILD_AND_RUN_EN.md      # Compilation instructions
│   └── PRESENTACION_ES.md / PRESENTACION_EN.md        # Student presentation
│
├── doc/                       # 📦 STUDENT SUBMISSION
│   └── README_ES.md / README_EN.md              # Submission instructions
│
├── build.gradle               # Gradle configuration
└── logging.properties         # Logging configuration
```

---

## 🎯 What to Implement?

### Files to Complete (in `src/agt/`)

1. **`robot_light.asl`** - Light robot logic
2. **`robot_medium.asl`** - Medium robot logic
3. **`robot_heavy.asl`** - Heavy robot logic
4. **`scheduler.asl`** - Task coordination and assignment
5. **`supervisor.asl`** - Monitoring and error management

### Provided Files

- All contents of `src/env/warehouse/` (Java environment)
- System configuration (`warehouse.mas2j`)

---

## 📚 Documentation

> **Note:** All documentation is available in **Spanish (_ES)** and **English (_EN)**.

### Getting Started:

1. **[initial_documentation/QUICKSTART_EN.md](initial_documentation/QUICKSTART_EN.md)** ([ES](initial_documentation/QUICKSTART_ES.md)) - Start here (step-by-step tutorial)
2. **[initial_documentation/README_EN.md](initial_documentation/README_EN.md)** ([ES](initial_documentation/README_ES.md)) - Complete project documentation
3. **[initial_documentation/PRESENTACION_EN.md](initial_documentation/PRESENTACION_EN.md)** ([ES](initial_documentation/PRESENTACION_ES.md)) - Project presentation

### During Development:

- **[initial_documentation/DEBUGGING_EN.md](initial_documentation/DEBUGGING_EN.md)** ([ES](initial_documentation/DEBUGGING_ES.md)) - Common problems and solutions
- **[initial_documentation/PROJECT_SUMMARY_EN.md](initial_documentation/PROJECT_SUMMARY_EN.md)** ([ES](initial_documentation/PROJECT_SUMMARY_ES.md)) - Project status
- **[initial_documentation/BUILD_AND_RUN_EN.md](initial_documentation/BUILD_AND_RUN_EN.md)** ([ES](initial_documentation/BUILD_AND_RUN_ES.md)) - Compilation and execution

### External Resources:

- [Jason Book](https://jason-lang.github.io/book/) (available on Moovi)
- [Official Jason Documentation](https://jason-lang.github.io)
- [Jason on GitHub](https://github.com/jason-lang/jason)

---

## 📦 Project Submission

### Submission Location

Place your documentation and solution in the **`doc/`** folder:

```
doc/
├── docs/ 
│   └── memory.pdf            # Technical project report
├── src/                      # Copy of your implemented code
│   └── agt/
│       ├── robot_light.asl
│       ├── robot_medium.asl
│       ├── robot_heavy.asl
│       ├── scheduler.asl
│       └── supervisor.asl
└── README.md                 # Specific instructions for your solution
```

### Report Contents Should Include

> The report is expected to have adequate technical quality and writing, with clear diagrams and detailed explanations. It should explain design decisions, agent logic, interaction between them, and how project objectives have been addressed. Additionally, it should include difficulties encountered and how they were solved, as well as references and possible future improvements if time permits.

> The report should be clear, concise, and well-structured, facilitating project understanding for any reader.

> It is not expected to be an extensive document, but rather complete and well-structured.

### Final Submission Format

Compress into a **ZIP** file with the following content:

- Complete `warehouse/` folder with your code
- `memoria.pdf` file in `doc/`

**File name:** `warehouse_groupXX.zip`

---

## Group Work

- Groups of up to **7 students**
- Use of Git/GitHub for collaboration is recommended
- All members must participate in the oral defense
- Submit on time (see Moovi for deadlines)

---

## 📄 License

Teaching material from the **University of Vigo** for the **Intelligent Systems** course.
