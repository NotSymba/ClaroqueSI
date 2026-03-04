# **Warehouse Management System - Quick Start Guide**

---

## Inicio en 5 Minutos

### 1. Verificar Instalación

```bash
# Verificar Java
java -version
# Debe mostrar Java 11 o superior

# Navegar al proyecto
cd /home/ivan/jason-3.3.0/projects/warehouse

# Listar archivos
ls -la
```

### 2. Ejecutar el Sistema

```bash
# Opción 1: Desde terminal
jason warehouse.mas2j

# Opción 2: Desde Jason directamente
# Abrir Jason GUI y cargar warehouse.mas2j
```

### 3. Observar el Sistema

Al ejecutar, verás:

1. **Ventana de visualización 2D**: Muestra el almacén con robots y contenedores
2. **Consola Jason**: Muestra logs de los agentes
3. **Panel de información**: Estadísticas en tiempo real

**Comportamiento inicial:**
- Los agentes están con plantillas vacías, así que no harán mucho
- Se generarán contenedores cada 5-10 segundos
- Los robots imprimirán mensajes pero no actuarán

---

## Tu Primera Implementación (30 minutos)

### Paso 1: Robot Básico (10 min)

Abre `src/agt/robot_light.asl` y descomenta/implementa:

```asl
// 1. Plan inicial
+!start : true <-
    .print("Robot ligero iniciado");
    !request_next_task.

// 2. Solicitar tareas
+!request_next_task : state(idle) <-
    request_task();
    .wait(2000);
    !request_next_task.

// 3. Reaccionar a tarea
+task(CId, ShelfId) : true <-
    .print("Tarea recibida: ", CId, " -> ", ShelfId);
    get_container_info(CId);
    // Por ahora, solo registrar
    true.
```

**Ejecuta y verifica:**
- ✓ Robot imprime "iniciado"
- ✓ Robot solicita tareas periódicamente

### Paso 2: Scheduler Básico (10 min)

Abre `src/agt/scheduler.asl`:

```asl
// 1. Reaccionar a nuevo contenedor
+new_container(CId) : true <-
    .print("Nuevo contenedor: ", CId);
    get_container_info(CId);
    true.

// 2. Recibir info y clasificar
+container_info(CId, W, H, Weight, Type) : true <-
    .print("Info: ", CId, " - ", Weight, "kg");
    +pending_container(CId, Weight).
```

**Ejecuta y verifica:**
- ✓ Scheduler detecta nuevos contenedores
- ✓ Obtiene información correctamente

### Paso 3: Conexión Scheduler-Robot (10 min)

En `scheduler.asl`, agregar asignación simple:

```asl
+container_info(CId, W, H, Weight, Type) : true <-
    .print("Clasificando ", CId);
    
    // Asignar a robot apropiado
    if (Weight <= 10) {
        .print("Asignando a robot_light");
        // Nota: Esta es una simplificación
        // El scheduler debería verificar disponibilidad
    }.
```

En `robot_light.asl`, completar la tarea:

```asl
+task(CId, ShelfId) : true <-
    .print("Ejecutando tarea: ", CId);
    
    // Paso 1: Ir al contenedor (simplificado)
    move_to(1, 1);  // Posición aproximada
    .wait(1000);
    
    // Paso 2: Recoger
    pickup(CId);
    .wait(1000);
    
    // Paso 3: Ir a estantería (simplificado)
    move_to(10, 2);
    .wait(1000);
    
    // Paso 4: Depositar
    drop_at(ShelfId).
```

**Ejecuta y verifica:**
- ✓ Robot recibe tarea
- ✓ Robot se mueve (ver en GUI)
- ✓ Robot recoge contenedor
- ✓ Robot deposita en estantería
