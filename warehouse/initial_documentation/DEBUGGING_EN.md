# Debugging Guide and Common Problem Solving

**Warehouse Project - University of Vigo**

---

## 🔍 Debugging Techniques in Jason

### 1. Using .print()

The most basic but effective debugging:

```asl
// Print variable values
+!my_plan : variable(X) <-
    .print("Value of X: ", X);
    ...

// Print at key points
+!complex_process : true <-
    .print("[DEBUG] Starting complex process");
    !step1;
    .print("[DEBUG] Step 1 completed");
    !step2;
    .print("[DEBUG] Step 2 completed").

// Print all current beliefs
+!debug_beliefs : true <-
    .print("=== CURRENT BELIEFS ===");
    .findall(B, B, BeliefList);
    .print(BeliefList).
```

### 2. Using Jason's Mind Inspector

Jason includes a visual tool to inspect agents:

1. Run the system
2. Right-click on the agent in Jason's GUI
3. Select "Mind Inspector"
4. View beliefs, plans, intentions in real-time

### 3. Breakpoints with .wait()

```asl
+!critical_phase : true <-
    .print("BREAKPOINT: Before critical action");
    .wait(5000);  // 5-second pause to observe
    critical_action().
```

---

## Common Problems and Solutions

### Problem 1: "Robot doesn't receive tasks"

**Symptoms:**
- Robot calls `request_task()` but never receives `+task(...)`
- Robot remains in `idle` state indefinitely

**Possible causes:**

1. **Scheduler is not assigning tasks**
   ```asl
   // Check in scheduler.asl
   +new_container(CId) : true <-
       ...
   ```

2. **No containers generated**
   - Automatic generator may take 5-10 seconds
   - Check in console: "New container generated: ..."

3. **Robot cannot handle available containers**
   ```asl
   // In scheduler, check assignment logic
   if (Weight <= 10 & robot_available(robot_light)) {
       .print("[SCHEDULER] Assigning to robot_light");
       ...
   }
   ```

**Solution:**
```asl
// In robot: add timeout and debug
+!request_next_task : state(idle) <-
```

---

### Problem 2: "Error: container_too_heavy"

**Symptoms:**
- Robot tries to pick up container
- Error: "container_too_heavy"

**Cause:**
Scheduler assigned a container that exceeds robot's capacity.

**Solution in scheduler.asl:**
```asl
+!assign_task(CId) : 
    container_info(CId, W, H, Weight, Type)
<-
```

---

### Problem 3: "Robot moves outside the grid"

**Symptoms:**
- Error: "illegal_move"
- "Position out of bounds"

**Cause:**
X,Y coordinates outside limits (0-19, 0-14).

**Solution:**
```asl
+!move_safe(X, Y) : true <-
```

---

### Problem 4: "Conflicts between robots"

**Symptoms:**
- Error: "conflict(robot_id)"
- Two robots try to occupy the same cell

**Basic solution:**
```asl
// Add random wait before moving
+!move_with_retry(X, Y) : true <-
    move_to(X, Y);
    .wait(math.random(1000)).  // Random wait 0-1s

// Advanced solution: passing protocol
+error(conflict, RobotData) : true <-
    .print("Conflict detected, waiting...");
    .wait(2000);
    !retry_movement.
```

---

### Problem 5: "Agent does not respond / Plan never executed"

**Symptoms:**
- Plan defined but never executes
- Agent doesn't respond to events

**Causes and solutions:**

1. **Goal not initiated**

2. **Incorrect syntax**

3. **Event not generated**

---

### Problem 6: "Infinite loop / Infinite recursion"

**Symptoms:**
- Console fills with repeated messages
- System freezes or slows down

**Common cause:**
```asl
// RECURSION WITHOUT STOP CONDITION
+!loop : true <-
    do_something();
    !loop.  // Careful! No way to stop
```

**Solution:**
```asl
// With stop condition
+!loop : counter(N) & N < 10 <-
    do_something();
    -+counter(N+1);
    !loop.

+!loop : counter(N) & N >= 10 <-
    .print("Loop finished").
    
// Or with state
+!loop : not must_stop <-
    do_something();
    .wait(1000);
    !loop.

+!loop : must_stop <-
    .print("Stopping loop").
```

---

### Problem 7: "Container/Shelf not found"

**Symptoms:**
- Error when trying to interact with container or shelf
- "Robot or container not found"

**Cause:**
Incorrect ID or wrong string format.

**Solution:**
```asl
// Verify IDs with quotes
pickup("container_1").  // CORRECT

// NOT this:
pickup(container_1).    // INCORRECT (without quotes)

```

---

## 📋 Debugging Checklist

When something doesn't work, check in order:

### □ 1. Syntax
- [ ] All plans end with a period (.)
- [ ] Correct use of quotes for strings
- [ ] Balanced parentheses and brackets
- [ ] Variable names with initial capital letter

### □ 2. Logic
- [ ] Plan contexts are met
- [ ] Goals initiated correctly
- [ ] Correct if/elif/else conditions
- [ ] No infinite recursion

### □ 3. Perceptions
- [ ] Correct perception names
- [ ] Correct data format
- [ ] Perceptions updated correctly

### □ 4. Communication
- [ ] Messages .send() have correct format
- [ ] Correct agent names
- [ ] Communication protocols implemented

### □ 5. State
- [ ] Agent state updated
- [ ] Beliefs reflect reality
- [ ] No contradictory beliefs

---

## 🛠️ Useful Tools

### Useful commands in plans

```asl
// Count beliefs
.count(belief_type(_), Amount)

// Find all beliefs of a type
.findall(X, my_belief(X), List)

// Current time
.time(Timestamp)

// Wait for condition
.wait(condition, Timeout)

// Broadcast to all
.broadcast(tell, message)

// Suspend plan
.suspend

// Resume plan
.resume
```

### System information

```asl
+!system_info : true <-
    .my_name(MyName);
    .print("My name: ", MyName);
    
    .all_names(AllAgents);
    .print("All agents: ", AllAgents);
    
    .intend(Intentions);
    .print("Current intentions: ", Intentions).
```

---

## 💡 Tips

1. **Use prefixes in logs:**
   ```asl
   .print("[ROBOT-LIGHT] Message here")
   .print("[SCHEDULER] Message there")
   ```

2. **Log levels:**
   ```asl
   .print("[INFO] Normal information")
   .print("[WARN] Warning")
   .print("[ERROR] Serious error")
   .print("[DEBUG] Only during development")
   ```

3. **Timestamps in important logs:**
   ```asl
   +important_event : true <-
       .time(T);
       .print("[", T, "] Important event occurred").
   ```

4. **Save previous states for rollback:**
   ```asl
   +!risky_operation : state(E) <-
       +previous_state(E);  // Backup
       !change_state;
       if (failed) {
           ?previous_state(PS);
           -+state(PS);  // Restore
       }.
   ```

---

## **Debugging is part of learning!**

---
