# Multi-Agent System for Automated Warehouse Logistics Management

**University of Vigo - Intelligent Systems**  
**Course 2025-2026**


## General Description

This project implements a **multi-agent system** for intelligent management of an automated logistics warehouse using **Jason/JaCaMo**. The system coordinates heterogeneous restocking robots to transport containers from entry zones to storage shelves.


## Graphical Interface (GUI)

The system includes a **real-time visualization** divided into three main areas:


### 🎨 Warehouse Map (Center)

**20×15 cell grid** with functional zones differentiated by colors:

| Color | Zone | Location | Function |
|-------|------|----------|----------|
| 🟢 **Light green** | Entry | Upper left corner (0-2, 0-1) | Container reception |
| 🟡 **Light yellow** | Classification | Top (3-6, 0-1) | Container processing |
| ⬜ **White/Gray** | Navigation | Rest of grid | Traversable spaces |
| 🟪 **Bluish gray** | Shelves | Specific areas | Storage |


### 🤖 Robots

**Represented as colored circles:**

- 🟢 **Green**: Light robot (10kg, 1×1) - High speed
- 🔵 **Blue**: Medium robot (30kg, 1×2) - Medium speed
- 🟣 **Magenta**: Heavy robot (100kg, 2×3) - Low speed

When a robot **is carrying a container**, a small yellow square is shown in its upper right corner.


### 📦 Containers

**Represented as small squares:**

- 🔵 **Blue**: Standard containers (70%)
- 🔴 **Light red**: Fragile containers (15%)
- 🟠 **Orange**: Urgent containers (15%)


### 📚 Shelves

**Rectangles with color coding according to occupancy:**

- 🟢 **Green**: < 50% occupied (available)
- 🟡 **Yellow**: 50-80% occupied (partially full)
- 🔴 **Red**: > 80% occupied (almost full)

Each shelf shows its **ID** and **occupancy percentage**.


### 📊 Information Panel (Right)

**Three sections updated in real-time:**

1. **Statistics**: Elapsed time, processed containers, pending, errors
2. **Robots**: Position, state (busy/free), current load
3. **Shelves**: Location, occupancy, weight, volume, stored items


### 📝 Activity Console (Bottom)

**Real-time log with timestamps** showing:

- ➡️ Robot movements
- 📦 Container pickups
- ✅ Successful storages
- 🆕 New container generation
- ❌ Errors and alerts

**Features:**
- Black background with green text (terminal style)
- Auto-scroll to latest messages
- 500 line limit (auto-cleanup)


## Project Objectives

Students must implement agent logic to:

1. ✅ Manage container reception and classification
2. ✅ Assign tasks to robots according to capabilities
3. ✅ Plan navigation routes
4. ✅ Avoid collisions between robots
5. ✅ Handle environment errors
6. ✅ Optimize warehouse efficiency
7. ✅ Monitor the system and generate metrics


## Project Structure

```
warehouse/
├── warehouse.mas2j              # Multi-agent system configuration
├── src/
│   ├── agt/                     # Agents (TO BE IMPLEMENTED)
│   │   ├── robot_light.asl      # Light robot
│   │   ├── robot_medium.asl     # Medium robot
│   │   ├── robot_heavy.asl      # Heavy robot
│   │   ├── scheduler.asl        # Task planner
│   │   └── supervisor.asl       # Monitor and error manager
│   └── env/warehouse/           # Environment (PROVIDED)
│       ├── WarehouseArtifact.java
│       ├── WarehouseView.java
│       ├── Container.java
│       ├── Shelf.java
│       ├── Robot.java
│       └── CellType.java
└── README.md
```


## System Components
- Restocking Robots
- Control Agents
- Containers
- Shelves


### Restocking Robots

| Robot        | Max Weight | Max Size | Speed | File               |
|--------------|------------|----------|-------|---------------------|
| `robot_light`  | 10 kg      | 1×1      | High (3) | `robot_light.asl`   |
| `robot_medium` | 30 kg      | 1×2      | Medium (2) | `robot_medium.asl`  |
| `robot_heavy`  | 100 kg     | 2×3      | Low (1) | `robot_heavy.asl`   |


### Control Agents

- **Scheduler** (`scheduler.asl`): Coordinates task assignment
- **Supervisor** (`supervisor.asl`): Monitors system and manages errors


### Containers

- **Sizes**: 1×1, 1×2, 2×2, 2×3
- **Weights**: 5 to 100 kg
- **Types**: `standard` (70%), `fragile` (15%), `urgent` (15%)
- **Generation**: automatic every 5-10 seconds


### Shelves

- Different weight and volume capacities
- Limited by available space
- Distributed in storage area


## Environment API (WarehouseArtifact)

### Available Actions

```asl
move_to(X, Y)              // Move robot to position (X,Y)
pickup(ContainerId)        // Pick up container
drop_at(ShelfId)           // Deposit on shelf
request_task()             // Request new task
get_container_info(CId)    // Get container info
get_free_shelf(CId)        // Find free shelf
scan_surroundings()        // Scan surroundings
```


### Received Perceptions

```asl
+robot_at(X,Y)                     // Updated position
+task(ContainerId, ShelfId)        // New task assigned
+picked(ContainerId)               // Container picked up
+stored(ContainerId, ShelfId)      // Container stored
+cell(X,Y,Type)                    // Cell information
+blocked(X,Y)                      // Blocked cell
+error(Type, Data)                 // Error occurred
+new_container(ContainerId)        // New container generated
+container_info(CId,W,H,Weight,Type) // Container info
```

### Error Types

- `container_too_heavy`: Robot cannot load due to weight
- `container_too_big`: Robot cannot load due to size
- `shelf_full`: Shelf has no space
- `illegal_move`: Movement out of bounds
- `conflict`: Collision with another robot
- `route_blocked`: Route blocked


## Project Execution

### Prerequisites

- **Java JDK** 21 or higher
- **Jason** 3.3.0 (installed in `/home/XXXX/jason-3.3.0/`)

### Compile and Run

```bash
# Navigate to project directory
cd /home/XXXX/jason-3.3.0/projects/warehouse

# Run with Jason
jason warehouse.mas2j
```


## Testing and Validation

### Test Cases

1. **Basic Test**: One robot, one container
2. **Multiple Test**: Three robots, multiple containers
3. **Capacity Test**: Containers only heavy robot can handle
4. **Error Test**: Full shelf, very heavy container
5. **Collision Test**: Two robots try to move to same place
6. **Load Test**: Rapid container generation


### Success Metrics

- ✅ **Documentation**: Complete and clear report
- ✅ **Functionality**: All containers are stored correctly
- ✅ **Efficiency**: Average time < 30 seconds per container
- ✅ **Robustness**: Error rate < 10%
- ✅ **Coordination**: No collisions or deadlocks
- ✅ **Utilization**: Idle robots < 30% of time


## Visualization

The system includes a **2D graphical interface** that shows:

- **Warehouse grid** with colored zones
- **Robots** as colored circles (green=light, blue=medium, magenta=heavy)
- **Containers** as squares (blue=normal, red=fragile, orange=urgent)
- **Shelves** with occupancy indicator (green < 50%, yellow 50-80%, red > 80%)
- **Information panel** with real-time statistics


## Evaluation Criteria

| Aspect                          | Weight | Description                                    |
|----------------------------------|--------|------------------------------------------------|
| **Functionality**                | 30%    | Complete and operational system                |
| **Multi-Agent Design**           | 20%    | Good architecture and role distribution        |
| **Knowledge Representation**     | 15%    | Correct use of beliefs, rules and plans        |
| **Error Handling**               | 15%    | Robust handling of anomalous situations        |
| **Efficiency**                   | 10%    | Resource and time optimization                 |
| **Code and Documentation**       | 10%    | Clean, commented and well-structured code      |


## Tips and Best Practices

### Development

- 🎯 **Incremental**: Implement basic functionality first, then optimize
- 🧪 **Test frequently**: Run after each major change
- 📝 **Comment**: Explain complex logic in comments
- 🔍 **Debug with prints**: Use `.print()` liberally during development


### Common Errors

- ❌ Not verifying capacity before assigning task
- ❌ Not updating robot state after actions
- ❌ Not handling cases where no robot is available
- ❌ Forgetting to mark robot as free after completing task
- ❌ Not considering distances in task assignment


### Advanced Optimizations

- 🚀 A* or Dijkstra route planning
- 🚀 Container arrival prediction
- 🚀 Task pre-assignment
- 🚀 Similar container batching
- 🚀 Traffic pattern learning


## Additional Resources

### Jason Documentation

- [Book "Programming Multi-Agent Systems in AgentSpeak using Jason"](https://jason-lang.github.io/book/) Available in Moovi.
- [Official Jason Documentation](https://jason-lang.github.io)
- [Jason (jason-lang/jason) Releases on GitHub](https://github.com/jason-lang/jason/releases)
- [Jason CLI Commands Reference](https://jason-lang.github.io/doc/jason-cli/commands.html)


### Key Concepts

- **Beliefs**: Agent's knowledge
- **Plans**: event : context <- actions
- **Perceptions**: Environment information
- **Actions**: Environment modification
- **Communication**: `.send()`, `.broadcast()`


## Problem Solving

### System doesn't start

```bash
# Check Java
java -version

# Check JASON_HOME
echo $JASON_HOME

# Recompile
cd /home/ivan/jason-3.3.0/projects/warehouse
jason warehouse.mas2j
```

### Agents don't communicate

- Verify that agent names in `.mas2j` match
- Use `[source(Agent)]` to identify sender
- Review `.send()` syntax


### Java compilation errors

```bash
# Verify classes are in correct package
# All environment classes should be in: warehouse/
```

### GUI doesn't show

- Verify there are no errors in Java code
- Check console for exceptions
- Ensure `WarehouseView` is instantiated correctly


## Team and Delivery

### Group Work

- Groups of up to **7 students**
- Distribute tasks
- Periodic meetings for integration
- Use of version control tools is recommended, such as GitHub, GitLab or Bitbucket


### Deliverables

1. **Complete source code**
2. **Project report**:
   - Multi-agent system design
   - Implementation decisions
   - Knowledge representation
   - Results analysis
   - Conclusions and future work
4. **Oral defense** of the project. All group members must participate.

### Warning

 :warning: A single project must be delivered per group, with complete code and report in PDF format. Everything must be compressed in a ZIP file.

:warning: Practices delivered late or not meeting required format will not be graded.


## Support

For questions or problems:

- **Course forums**: moovi.uvigo.es
- **Email**: ivan.luis@uvigo.es


## License

This project is teaching material from the **University of Vigo** for the **Intelligent Systems** course.
