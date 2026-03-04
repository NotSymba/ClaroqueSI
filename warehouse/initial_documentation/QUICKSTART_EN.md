# **Warehouse Management System - Quick Start Guide**

---

## 5-Minute Start

### 1. Verify Installation

```bash
# Check Java
java -version
# Should show Java 11 or higher

# Navigate to project
cd /home/ivan/jason-3.3.0/projects/warehouse

# List files
ls -la
```

### 2. Run the System

```bash
# Option 1: From terminal
jason warehouse.mas2j

# Option 2: From Jason directly
# Open Jason GUI and load warehouse.mas2j
```

### 3. Observe the System

When running, you will see:

1. **2D visualization window**: Shows the warehouse with robots and containers
2. **Jason console**: Shows agent logs
3. **Information panel**: Real-time statistics

**Initial behavior:**
- Agents have empty templates, so they won't do much
- Containers will be generated every 5-10 seconds
- Robots will print messages but won't act

---

## Your First Implementation (30 minutes)

### Step 1: Basic Robot (10 min)

Open `src/agt/robot_light.asl` and uncomment/implement:

```asl
// 1. Initial plan
+!start : true <-
    .print("Light robot started");
    !request_next_task.

// 2. Request tasks
+!request_next_task : state(idle) <-
    request_task();
    .wait(2000);
    !request_next_task.

// 3. React to task
+task(CId, ShelfId) : true <-
    .print("Task received: ", CId, " -> ", ShelfId);
    get_container_info(CId);
    // For now, just log
    true.
```

**Run and verify:**
- ✓ Robot prints "started"
- ✓ Robot requests tasks periodically

### Step 2: Basic Scheduler (10 min)

Open `src/agt/scheduler.asl`:

```asl
// 1. React to new container
+new_container(CId) : true <-
    .print("New container: ", CId);
    get_container_info(CId);
    true.

// 2. Receive info and classify
+container_info(CId, W, H, Weight, Type) : true <-
    .print("Info: ", CId, " - ", Weight, "kg");
    +pending_container(CId, Weight).
```

**Run and verify:**
- ✓ Scheduler detects new containers
- ✓ Gets information correctly

### Step 3: Scheduler-Robot Connection (10 min)

In `scheduler.asl`, add simple assignment:

```asl
+container_info(CId, W, H, Weight, Type) : true <-
    .print("Classifying ", CId);
    
    // Assign to appropriate robot
    if (Weight <= 10) {
        .print("Assigning to robot_light");
        // Note: This is a simplification
        // Scheduler should check availability
    }.
```

In `robot_light.asl`, complete the task:

```asl
+task(CId, ShelfId) : true <-
    .print("Executing task: ", CId);
    
    // Step 1: Go to container (simplified)
    move_to(1, 1);  // Approximate position
    .wait(1000);
    
    // Step 2: Pick up
    pickup(CId);
    .wait(1000);
    
    // Step 3: Go to shelf (simplified)
    move_to(10, 2);
    .wait(1000);
    
    // Step 4: Drop
    drop_at(ShelfId).
```

**Run and verify:**
- ✓ Robot receives task
- ✓ Robot moves (see in GUI)
- ✓ Robot picks up container
- ✓ Robot drops at shelf

---

## Next Steps

### After the Quick Start

1. **Implement complete logic** for all three robot types
2. **Improve scheduler** with availability checking
3. **Add supervisor** for error handling
4. **Optimize** task assignment
5. **Test** edge cases

### Recommended Reading Order

1. `README_EN.md` (or `README_ES.md`) - Complete documentation
2. `DEBUGGING_EN.md` (or `DEBUGGING_ES.md`) - When you encounter problems
3. Jason documentation - For advanced features

---

## Common Initial Problems

### Problem: "No task received"

**Solution:** Check that the scheduler is assigning tasks correctly and using `.send()` or `.broadcast()` to communicate.

### Problem: "Robot doesn't move"

**Solution:** Verify that `move_to(X,Y)` coordinates are within the grid (0-19, 0-14).

### Problem: "Container not picked up"

**Solution:** Check that:
- Robot is at the correct position
- Container still exists
- Robot has sufficient capacity

---

## Quick Test Checklist

- [ ] System runs without errors
- [ ] Containers appear in the GUI
- [ ] Robots print messages
- [ ] Scheduler detects containers
- [ ] Robots receive tasks
- [ ] Robots move in the GUI
- [ ] Containers are picked up
- [ ] Containers are stored

---

## Tips for Rapid Development

✅ **Use `.print()` extensively** for debugging

✅ **Test after each small change**

✅ **Start simple, add complexity gradually**

✅ **Keep Jason console visible** to see errors

✅ **Check GUI to verify visual behavior**

---

## Ready?

🚀 You're ready to start developing your multi-agent warehouse system!

**Remember:** It's normal to encounter errors. Use `DEBUGGING_EN.md` (or `DEBUGGING_ES.md`) when you get stuck.

**Good luck! 🤖**
