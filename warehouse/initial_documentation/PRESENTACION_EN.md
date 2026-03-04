---
marp: true
title: Warehouse Management System - Presentation
theme: default
paginate: true
backgroundColor: '#f9fcffff'
color: '#140b3dff'
---

# Multi-Agent System for Warehouse Management

**University of Vigo - Intelligent Systems**  
**Course 2025-2026**

**Platform:** Jason/JaCaMo 3.3.0  
**Language:** AgentSpeak + Java

---

## What will you implement?

An **intelligent multi-agent system** that coordinates autonomous robots in an automated warehouse.

**Main tasks:**
- Coordinate 3 robot types with different capacities
- Manage containers of different sizes and weights
- Optimize storage on shelves
- Handle errors and exceptional situations
- Monitor the system in real-time

---

## The 3 Robots

| Robot | Capacity | Max Size | Speed | GUI Color |
|-------|----------|----------|-------|-----------|
| **Light** | 10 kg | 1×1 | High (3) | 🟢 Green |
| **Medium** | 30 kg | 1×2 | Medium (2) | 🔵 Blue |
| **Heavy** | 100 kg | 2×3 | Low (1) | 🟣 Magenta |

**Objective:** Assign the appropriate robot according to the container.

---

## Containers

**Automatic generation** every 5-10 seconds

**Features:**
- **Sizes:** 1×1, 1×2, 2×2, 2×3
- **Weights:** 5 to 100 kg
- **Types:**
  - 🔵 Standard (70%) - Normal
  - 🔴 Fragile (15%) - Requires special care
  - 🟠 Urgent (15%) - High priority

---

## The environment: warehouse with 20×15 grid

**Functional zones:**

| Zone | Color | Location | Function |
|------|-------|----------|----------|
| 🟢 **Entry** | Light green | (0-2, 0-1) | Reception |
| 🟡 **Classification** | Yellow | (3-6, 0-1) | Processing |
| ⬜ **Navigation** | White/Gray | Rest | Transit |
| 🟪 **Shelves** | Bluish gray | Distributed | Storage |

---

## The agents

### Robots (3 agents)
- `robot_light.asl` - Light robot
- `robot_medium.asl` - Medium robot
- `robot_heavy.asl` - Heavy robot

### Coordinators (2 agents)
- `scheduler.asl` - **Assigns tasks** to robots
- `supervisor.asl` - **Monitors** and manages errors

---

## Workflow

```
1. Container appears in entry zone
   ↓
2. Scheduler classifies it (weight, size, type)
   ↓
3. Scheduler assigns appropriate robot
   ↓
4. Robot receives task (container → shelf)
   ↓
5. Robot executes: move → pick up → move → deposit
   ↓
6. Robot requests new task
   ↓
7. Supervisor monitors the entire process
```

---

## 🛠️ Environment External Actions

```asl
// Movement
move_to(X, Y)                  // Move to position

// Manipulation
pickup(ContainerId)            // Pick up container
drop_at(ShelfId)               // Drop at shelf

// Information
request_task()                 // Request new task
get_container_info(CId)        // Container info
get_free_shelf(CId)            // Find available shelf
scan_surroundings()            // Explore around
```

---

## Environment Perceptions

```asl
+robot_at(X,Y)                      // My updated position
+task(ContainerId, ShelfId)         // New task assigned
+picked(ContainerId)                // Container picked up
+stored(ContainerId, ShelfId)       // Successful storage

+new_container(ContainerId)         // New container generated
+container_info(CId,W,H,Weight,Type) // Container details

+error(Type, Data)                  // Error detected
+blocked(X,Y)                       // Route blocked
```

---

## Error Handling

```asl
+error(container_too_heavy, Data)  // Robot too light
+error(container_too_big, Data)    // Robot too small
+error(shelf_full, Data)           // No space
+error(illegal_move, Data)         // Out of bounds
+error(conflict, Data)             // Collision between robots
+error(route_blocked, Data)        // Path obstructed
```

**Important:** agents must handle at least these errors.

---

## Real-Time GUI

**3 main areas:**

1. **Center:** Warehouse grid with robots, containers and shelves
2. **Right:** Information panel
   - Statistics (time, processed, errors)
   - State of each robot
   - Shelf occupancy
3. **Bottom:** Activity console with timestamps

---

## File Structure

```
warehouse/
├── warehouse.mas2j              # MAS configuration
├── src/
│   ├── agt/                     # Jason agents
│   │   ├── robot_light.asl
│   │   ├── robot_medium.asl
│   │   ├── robot_heavy.asl
│   │   ├── scheduler.asl
│   │   └── supervisor.asl
│   └── env/warehouse/           # Provided environment
│       └── ... (Java files)
└── docs/                        # Documentation
```

---

## How to Run

```bash
# Navigate to project
cd /home/XXXX/jason-3.3.0/projects/warehouse

# Run (will open GUI automatically)
jason warehouse.mas2j
```

**Requirements:**
- Java 21+
- Jason 3.3.0

---

## Your Objectives

### Basic Functionality
- Robots receive and execute tasks
- Scheduler assigns according to capabilities
- All containers are stored
- Basic error handling

---

## Your Objectives
### Advanced Functionality
- Intelligent route planning
- Avoid collisions between robots
- Prioritization by container type
- Shelf optimization
- Efficiency metrics

---

## Available Resources

**Project documentation:**
- `README_ES.md` / `README_EN.md` - Complete project guide
- `QUICKSTART_ES.md` / `QUICKSTART_EN.md` - Quick start
- `DEBUGGING_ES.md` / `DEBUGGING_EN.md` - Common problem solving
- `PROJECT_SUMMARY_ES.md` / `PROJECT_SUMMARY_EN.md` - Project status summary

**External resources:**
- [Jason Book](https://jason-lang.github.io/book/) (Moovi)
- [Official Jason Documentation](https://jason-lang.github.io)
- [Jason GitHub](https://github.com/jason-lang/jason)

---

## Practical Tips

### During development:
- Use `.print()` extensively for debug
- Test after each change
- Comment complex logic
- Start simple, then optimize

### Common errors:
- Not verifying capacity before assigning
- Not updating robot state
- Not handling case without available robots
- Forgetting to request new task

---

## Evaluation Criteria

| Aspect | Key |
|--------|-----|
| **Functionality** | Complete operational system |
| **Multi-Agent Design** | Good architecture |
| **Knowledge Representation** | Beliefs and plans |
| **Error Handling** | Robustness |
| **Efficiency** | Optimization |
| **Code and Docs** | Clean and documented |

---

## Group Work

**Configuration:**
- Groups of up to **7 students**
- **Recommended:** Git/GitHub to collaborate

**Suggested distribution:**
- 3 people → Robots (1 per type)
- 2 people → Scheduler
- 1 person → Supervisor
- 1 person → Documentation and testing

---

## Deliverables

1. **Complete source code** (implemented `.asl`)
2. **Technical report** (PDF):
   - System design
   - Implementation decisions
   - Knowledge representation
   - Results analysis
   - Conclusions
3. **Oral defense** (all members participate)

> :warning: **Delivery format:** One ZIP with the entire project with expected structure + PDF report in docs/ directory

---

## **Remember:**
- Start simple, then optimize
- Test frequently
- Work as a team
- Ask when you have questions

---

# Questions?

📧 ivan.luis@uvigo.es  
💬 Moovi Forums  
📚 Documentation in the project
