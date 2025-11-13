# 🌐 Implementación del Endpoint /GetMovilActivo

## 📋 Resumen

Endpoint necesario para el **sistema de recuperación automática de MovilId** cuando el servicio GPS se queda sin datos.

---

## 🎯 Especificación del Endpoint

### URL
```
POST /ica_geos_/appservices/GetMovilActivo
```

### Request Body (JSON)
```json
{
  "DeviceId": "ed90b721e7b3444d"
}
```

### Response Body (JSON)

#### ✅ Éxito (HTTP 200)
```json
{
  "MovilId": "693"
}
```

#### ❌ No encontrado (HTTP 404)
```json
{
  "error": {
    "code": 404,
    "message": "No hay sesión activa para este dispositivo"
  }
}
```

#### ❌ Error del servidor (HTTP 500)
```json
{
  "error": {
    "code": 500,
    "message": "Error interno del servidor"
  }
}
```

---

## 🛠️ Lógica de Implementación

### SQL Query Sugerido
```sql
SELECT TOP 1 
    MovilId,
    Usuario,
    FechaInicio,
    UltimaActividad
FROM 
    SesionesActivas
WHERE 
    DeviceId = @DeviceId
    AND Estado = 'Activa'
    AND FechaCierre IS NULL
ORDER BY 
    FechaInicio DESC
```

### Pseudocódigo (C# / ASP.NET)
```csharp
[HttpPost]
[Route("GetMovilActivo")]
public IActionResult GetMovilActivo([FromBody] GetMovilActivoRequest request)
{
    try
    {
        // Validar que DeviceId no esté vacío
        if (string.IsNullOrWhiteSpace(request.DeviceId))
        {
            return BadRequest(new { 
                error = new { 
                    code = 400, 
                    message = "DeviceId es requerido" 
                } 
            });
        }

        // Buscar sesión activa en base de datos
        var sesion = _dbContext.SesionesActivas
            .Where(s => s.DeviceId == request.DeviceId 
                     && s.Estado == "Activa" 
                     && s.FechaCierre == null)
            .OrderByDescending(s => s.FechaInicio)
            .FirstOrDefault();

        if (sesion == null)
        {
            // No hay sesión activa para este dispositivo
            return NotFound(new { 
                error = new { 
                    code = 404, 
                    message = "No hay sesión activa para este dispositivo" 
                } 
            });
        }

        // Actualizar timestamp de última actividad (opcional pero recomendado)
        sesion.UltimaActividad = DateTime.Now;
        _dbContext.SaveChanges();

        // Log para auditoría
        _logger.LogInformation(
            "Recovery API: MovilId {MovilId} recuperado para DeviceId {DeviceId}", 
            sesion.MovilId, 
            request.DeviceId
        );

        // Retornar MovilId
        return Ok(new { MovilId = sesion.MovilId.ToString() });
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Error recuperando MovilId para DeviceId {DeviceId}", request.DeviceId);
        
        return StatusCode(500, new { 
            error = new { 
                code = 500, 
                message = "Error interno del servidor" 
            } 
        });
    }
}

// DTO
public class GetMovilActivoRequest
{
    public string DeviceId { get; set; }
}
```

---

## 🔒 Seguridad y Validaciones

### ✅ Validaciones Requeridas
1. **DeviceId no vacío**: Retornar HTTP 400 si falta
2. **Formato de DeviceId**: Validar que sea alfanumérico (opcional)
3. **Sesión única activa**: Solo debe haber 1 sesión activa por DeviceId
4. **Estado = 'Activa'**: Ignorar sesiones cerradas o inactivas
5. **FechaCierre IS NULL**: Asegurar que la sesión no esté finalizada

### 🛡️ Consideraciones de Seguridad
- **Rate Limiting**: Limitar a 10 requests por minuto por DeviceId
- **Logging**: Registrar todos los intentos de recuperación para auditoría
- **Timeout**: No debería tardar más de 3 segundos
- **HTTPS obligatorio**: No exponer en HTTP

---

## 📊 Tabla de Base de Datos Sugerida

Si no tienes una tabla de sesiones activas, considera crearla:

```sql
CREATE TABLE SesionesActivas (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    DeviceId NVARCHAR(50) NOT NULL,
    MovilId INT NOT NULL,
    Usuario NVARCHAR(100) NOT NULL,
    Escenario INT NOT NULL,
    FechaInicio DATETIME NOT NULL DEFAULT GETDATE(),
    FechaCierre DATETIME NULL,
    UltimaActividad DATETIME NOT NULL DEFAULT GETDATE(),
    Estado NVARCHAR(20) NOT NULL DEFAULT 'Activa',
    VersionApp NVARCHAR(20) NULL,
    
    INDEX IX_DeviceId_Estado (DeviceId, Estado),
    INDEX IX_UltimaActividad (UltimaActividad)
);
```

### Triggers o Stored Procedures Recomendados
- **Al hacer login**: Insertar registro en `SesionesActivas`
- **Al hacer logout**: Actualizar `FechaCierre` y `Estado = 'Cerrada'`
- **Limpieza automática**: Job para cerrar sesiones con `UltimaActividad > 24 horas`

---

## 🧪 Pruebas con Postman/curl

### Request
```bash
curl -X POST https://www.riogas.uy/ica_geos_/appservices/GetMovilActivo \
  -H "Content-Type: application/json" \
  -d '{"DeviceId":"ed90b721e7b3444d"}'
```

### Response Esperada (200 OK)
```json
{
  "MovilId": "693"
}
```

### Response Esperada (404 Not Found)
```json
{
  "error": {
    "code": 404,
    "message": "No hay sesión activa para este dispositivo"
  }
}
```

---

## 📈 Monitoreo y Logs

### Métricas a Monitorear
- **Requests por minuto**: Para detectar abuso
- **Tasa de éxito vs 404**: Para ver cuántas sesiones están activas
- **Tiempo de respuesta**: Debe ser < 500ms
- **Errores 500**: Indicador de problemas en BD

### Logs Recomendados
```
[INFO] Recovery API: MovilId 693 recuperado para DeviceId ed90b721e7b3444d
[WARN] Recovery API: No se encontró sesión activa para DeviceId abc123
[ERROR] Recovery API: Error en BD - Timeout consultando SesionesActivas
```

---

## 🔗 Integración con Sistema Existente

### Dónde se Invoca
- **MovilRecoveryHelper.kt** (Android nativo)
- **ServiceWatchdog.kt** (cuando GPS service muere)
- **ForegroundLocationService.kt** (al iniciar servicio GPS)

### Cuándo se Llama
1. GPS service muere y `movil` está vacío en SharedPreferences
2. `deviceId` se recuperó exitosamente
3. Intentos de recuperación local (Flutter/Native SharedPreferences) fallaron

### Flujo Completo
```
1. GPS Service detecta que movil está vacío
2. ServiceWatchdog intenta recuperar deviceId
3. MovilRecoveryHelper intenta:
   a. Leer movil desde Flutter SharedPreferences ❌
   b. Leer movil desde Native SharedPreferences ❌
   c. Llamar API /GetMovilActivo ✅ (último recurso)
4. Si API retorna MovilId:
   - Se guarda en SharedPreferences (Flutter + Native)
   - Se reinicia GPS service con movil recuperado
   - Se loguea éxito en CriticalLogger → n8n
```

---

## ⚠️ Casos Límite

### 1. Múltiples Sesiones Activas
Si hay más de una sesión activa para el mismo DeviceId:
- **Retornar la más reciente** (`ORDER BY FechaInicio DESC`)
- **Alertar al equipo** (podría indicar bug en el sistema de login)

### 2. Sesión Expirada
Si la última actividad fue hace más de X horas:
- **Cerrar sesión automáticamente**
- **Retornar 404**
- **Loguear para auditoría**

### 3. DeviceId Malicioso
Si el DeviceId no tiene formato válido:
- **Retornar 400 Bad Request**
- **Loguear intento sospechoso**

---

## 🚀 Roadmap de Implementación

### Fase 1: Backend (URGENTE) ⚠️
1. ✅ Crear endpoint `/GetMovilActivo`
2. ✅ Implementar query a base de datos
3. ✅ Agregar validaciones
4. ✅ Configurar logging
5. ✅ Probar con Postman/curl

### Fase 2: Testing (Alta Prioridad)
1. ✅ Simular movil vacío en producción
2. ✅ Verificar que deviceId se recupera
3. ✅ Verificar que API se llama correctamente
4. ✅ Confirmar que GPS service se reinicia

### Fase 3: Monitoreo (Media Prioridad)
1. ✅ Configurar alertas en n8n para `MOVIL_RECOVERY_API_SUCCESS`
2. ✅ Dashboard de métricas de recuperación
3. ✅ Analizar tasa de éxito/fallo

---

## 📞 Contacto y Soporte

Si tienes dudas sobre la implementación, contacta al equipo móvil.

**Archivo relacionado en Android**: `MovilRecoveryHelper.kt` (líneas 190-250)
