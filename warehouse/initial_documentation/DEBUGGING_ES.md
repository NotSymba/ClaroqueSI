# Guía de Debugging y Solución de Problemas Comunes

**Proyecto Warehouse - Universidad de Vigo**

---

## 🔍 Técnicas de Debugging en Jason

### 1. Uso de .print()

El debugging más básico pero efectivo:

```asl
// Imprimir valores de variables
+!mi_plan : variable(X) <-
    .print("Valor de X: ", X);
    ...

// Imprimir en puntos clave
+!proceso_complejo : true <-
    .print("[DEBUG] Iniciando proceso complejo");
    !paso1;
    .print("[DEBUG] Paso 1 completado");
    !paso2;
    .print("[DEBUG] Paso 2 completado").

// Imprimir todas las creencias actuales
+!debug_beliefs : true <-
    .print("=== CREENCIAS ACTUALES ===");
    .findall(B, B, ListaCreencias);
    .print(ListaCreencias).
```

### 2. Uso de Mind Inspector de Jason

Jason incluye una herramienta visual para inspeccionar agentes:

1. Ejecutar el sistema
2. Click derecho en el agente en la GUI de Jason
3. Seleccionar "Mind Inspector"
4. Ver creencias, planes, intenciones en tiempo real

### 3. Breakpoints con .wait()

```asl
+!fase_critica : true <-
    .print("BREAKPOINT: Antes de acción crítica");
    .wait(5000);  // Pausa de 5 segundos para observar
    accion_critica().
```

---

## Problemas Comunes y Soluciones

### Problema 1: "Robot no recibe tareas"

**Síntomas:**
- Robot llama `request_task()` pero nunca recibe `+task(...)`
- Robot permanece en estado `idle` indefinidamente

**Causas posibles:**

1. **Scheduler no está asignando tareas**
   ```asl
   // Verificar en scheduler.asl
   +new_container(CId) : true <-
       ...
   ```

2. **No hay contenedores generados**
   - El generador automático puede tardar 5-10 segundos
   - Verificar en consola: "New container generated: ..."

3. **Robot no es capaz de manejar contenedores disponibles**
   ```asl
   // En scheduler, verificar lógica de asignación
   if (Weight <= 10 & robot_available(robot_light)) {
       .print("[SCHEDULER] Asignando a robot_light");
       ...
   }
   ```

**Solución:**
```asl
// En robot: agregar timeout y debug
+!request_next_task : state(idle) <-
```

---

### Problema 2: "Error: container_too_heavy"

**Síntomas:**
- Robot intenta recoger contenedor
- Error: "container_too_heavy"

**Causa:**
El scheduler asignó un contenedor que excede la capacidad del robot.

**Solución en scheduler.asl:**
```asl
+!assign_task(CId) : 
    container_info(CId, W, H, Weight, Type)
<-
```

---

### Problema 3: "Robot se mueve fuera del grid"

**Síntomas:**
- Error: "illegal_move"
- "Position out of bounds"

**Causa:**
Coordenadas X,Y fuera de los límites (0-19, 0-14).

**Solución:**
```asl
+!move_safe(X, Y) : true <-
```

---

### Problema 4: "Conflictos entre robots"

**Síntomas:**
- Error: "conflict(robot_id)"
- Dos robots intentan ocupar la misma celda

**Solución básica:**
```asl
// Agregar espera aleatoria antes de moverse
+!move_with_retry(X, Y) : true <-
    move_to(X, Y);
    .wait(math.random(1000)).  // Espera aleatoria 0-1s

// Solución avanzada: protocol de paso
+error(conflict, RobotData) : true <-
    .print("Conflicto detectado, esperando...");
    .wait(2000);
    !retry_movement.
```

---


### Problema 5: "Agent does not respond / Plan never executed"

**Síntomas:**
- Plan definido pero nunca se ejecuta
- Agente no responde a eventos

**Causas y soluciones:**

1. **Objetivo no iniciado**

2. **Sintaxis incorrecta**

3. **Evento no se genera**

---

### Problema 6: "Infinite loop / Recursión infinita"

**Síntomas:**
- Consola se llena de mensajes repetidos
- Sistema se congela o ralentiza

**Causa común:**
```asl
// RECURSIÓN SIN CONDICIÓN DE PARADA
+!loop : true <-
    hacer_algo();
    !loop.  // ¡Cuidado! No hay forma de parar
```

**Solución:**
```asl
// Con condición de parada
+!loop : contador(N) & N < 10 <-
    hacer_algo();
    -+contador(N+1);
    !loop.

+!loop : contador(N) & N >= 10 <-
    .print("Loop terminado").
    
// O con estado
+!loop : not debe_parar <-
    hacer_algo();
    .wait(1000);
    !loop.

+!loop : debe_parar <-
    .print("Deteniendo loop").
```

---

### Problema 7: "Container/Shelf not found"

**Síntomas:**
- Error cuando se intenta interactuar con contenedor o estantería
- "Robot or container not found"

**Causa:**
ID incorrecto o formato de string erróneo.

**Solución:**
```asl
// Verificar IDs con comillas
pickup("container_1").  // CORRECTO

// NO esto:
pickup(container_1).    // INCORRECTO (sin comillas)

```

---

## 📋 Checklist de Debugging

Cuando algo no funciona, revisar en orden:

### □ 1. Sintaxis
- [ ] Todos los planes terminan en punto (.)
- [ ] Uso correcto de comillas para strings
- [ ] Paréntesis y corchetes balanceados
- [ ] Nombres de variables con mayúscula inicial

### □ 2. Lógica
- [ ] Contextos de planes se cumplen
- [ ] Objetivos se inician correctamente
- [ ] Condiciones if/elif/else correctas
- [ ] No hay recursión infinita

### □ 3. Percepciones
- [ ] Nombres de percepciones correctos
- [ ] Formato de datos correcto
- [ ] Percepciones se actualizan correctamente

### □ 4. Comunicación
- [ ] Mensajes .send() tienen formato correcto
- [ ] Nombres de agentes correctos
- [ ] Protocolos de comunicación implementados

### □ 5. Estado
- [ ] Estado del agente se actualiza
- [ ] Creencias reflejan la realidad
- [ ] No hay creencias contradictorias

---

## 🛠️ Herramientas Útiles

### Comando útiles en planes

```asl
// Contar creencias
.count(tipo_creencia(_), Cantidad)

// Buscar todas las creencias de un tipo
.findall(X, mi_creencia(X), Lista)

// Tiempo actual
.time(Timestamp)

// Esperar condición
.wait(condicion, Timeout)

// Broadcast a todos
.broadcast(tell, mensaje)

// Suspender plan
.suspend

// Reanudar plan
.resume
```

### Información del sistema

```asl
+!system_info : true <-
    .my_name(MyName);
    .print("Mi nombre: ", MyName);
    
    .all_names(AllAgents);
    .print("Todos los agentes: ", AllAgents);
    
    .intend(Intentions);
    .print("Intenciones actuales: ", Intentions).
```

---

## 💡 Consejos

1. **Usa prefijos en logs:**
   ```asl
   .print("[ROBOT-LIGHT] Mensaje aquí")
   .print("[SCHEDULER] Mensaje allá")
   ```

2. **Niveles de log:**
   ```asl
   .print("[INFO] Información normal")
   .print("[WARN] Advertencia")
   .print("[ERROR] Error grave")
   .print("[DEBUG] Solo durante desarrollo")
   ```

3. **Timestamps en logs importantes:**
   ```asl
   +evento_importante : true <-
       .time(T);
       .print("[", T, "] Evento importante ocurrido").
   ```

4. **Guarda estados previos para rollback:**
   ```asl
   +!operacion_arriesgada : estado(E) <-
       +estado_previo(E);  // Backup
       !cambiar_estado;
       if (fallo) {
           ?estado_previo(EP);
           -+estado(EP);  // Restaurar
       }.
   ```

---


## **Debugging es parte del aprendizaje!** 

---





















