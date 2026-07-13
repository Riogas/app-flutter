package com.example.moveit

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.*

/**
 * Sistema de logging nativo para el servicio de ubicación
 * Guarda logs en SQLite y archivos para posterior sincronización con Hive
 */
object LocationLogger {
    private const val TAG = "LocationLogger"
    const val DB_NAME = "location_logs.db"
    const val DB_VERSION = 1
    private const val TABLE_LOGS = "location_logs"
    private const val TABLE_ERRORS = "location_errors"
    private const val TABLE_METRICS = "location_metrics"
    
    private var dbHelper: LocationLogDBHelper? = null
    
    /**
     * Inicializa el sistema de logging
     */
    fun initialize(context: Context) {
        try {
            dbHelper = LocationLogDBHelper(context)
            Log.i(TAG, "✅ Sistema de logging inicializado")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error inicializando logging", e)
        }
    }
    
    /**
     * Registra un evento general
     */
    fun logEvent(context: Context, eventType: String, data: Map<String, String> = emptyMap()) {
        try {
            if (dbHelper == null) initialize(context)
            
            val db = dbHelper?.writableDatabase
            val timestamp = System.currentTimeMillis()
            val dateStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(timestamp))
            
            // Crear JSON con los datos
            val jsonData = JSONObject(data).toString()
            
            // Insertar en SQLite
            db?.execSQL("""
                INSERT INTO $TABLE_LOGS (timestamp, date_str, event_type, data, synced) 
                VALUES (?, ?, ?, ?, 0)
            """, arrayOf(timestamp, dateStr, eventType, jsonData))
            
            // También guardar en archivo como respaldo
            writeToLogFile(context, "EVENT", eventType, jsonData)
            
            Log.d(TAG, "📝 Evento registrado: $eventType")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error registrando evento", e)
        }
    }
    
    /**
     * Registra un error
     */
    fun logError(context: Context, errorType: String, errorMessage: String, stackTrace: String? = null) {
        try {
            if (dbHelper == null) initialize(context)
            
            val db = dbHelper?.writableDatabase
            val timestamp = System.currentTimeMillis()
            val dateStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(timestamp))
            
            // Insertar en SQLite
            db?.execSQL("""
                INSERT INTO $TABLE_ERRORS (timestamp, date_str, error_type, error_message, stack_trace, synced) 
                VALUES (?, ?, ?, ?, ?, 0)
            """, arrayOf(timestamp, dateStr, errorType, errorMessage, stackTrace ?: ""))
            
            // También guardar en archivo como respaldo
            val errorData = mapOf(
                "type" to errorType,
                "message" to errorMessage,
                "stack_trace" to (stackTrace ?: "")
            )
            writeToLogFile(context, "ERROR", errorType, JSONObject(errorData).toString())
            
            // Actualizar contador de errores
            updateErrorCount(context)
            
            Log.e(TAG, "🚨 Error registrado: $errorType - $errorMessage")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error registrando error", e)
        }
    }
    
    /**
     * Registra métricas de ubicación
     */
    fun logLocationMetric(context: Context, lat: Double, lon: Double, provider: String, accuracy: Float, speed: Float) {
        try {
            if (dbHelper == null) initialize(context)
            
            val db = dbHelper?.writableDatabase
            val timestamp = System.currentTimeMillis()
            val dateStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(timestamp))
            
            // Insertar en SQLite
            db?.execSQL("""
                INSERT INTO $TABLE_METRICS (timestamp, date_str, latitude, longitude, provider, accuracy, speed, synced) 
                VALUES (?, ?, ?, ?, ?, ?, ?, 0)
            """, arrayOf(timestamp, dateStr, lat, lon, provider, accuracy, speed))
            
            // También guardar en archivo
            val metricData = mapOf(
                "lat" to lat.toString(),
                "lon" to lon.toString(),
                "provider" to provider,
                "accuracy" to accuracy.toString(),
                "speed" to speed.toString()
            )
            writeToLogFile(context, "METRIC", "LOCATION", JSONObject(metricData).toString())
            
            Log.d(TAG, "📊 Métrica registrada: $provider ($lat, $lon)")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error registrando métrica", e)
        }
    }
    
    /**
     * Escribe logs a archivo como respaldo
     */
    private fun writeToLogFile(context: Context, logType: String, eventType: String, data: String) {
        try {
            val logDir = File(context.filesDir, "location_logs")
            if (!logDir.exists()) {
                logDir.mkdirs()
            }
            
            val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            val fileName = "location_${dateFormat.format(Date())}.log"
            val logFile = File(logDir, fileName)
            
            val timestamp = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault()).format(Date())
            val logEntry = "[$timestamp] $logType:$eventType - $data\n"
            
            FileWriter(logFile, true).use { writer ->
                writer.append(logEntry)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error escribiendo archivo de log", e)
        }
    }
    
    /**
     * Actualiza el contador de errores
     */
    private fun updateErrorCount(context: Context) {
        try {
            val prefs = context.getSharedPreferences("location_errors", Context.MODE_PRIVATE)
            val currentCount = prefs.getInt("error_count", 0)
            prefs.edit().apply {
                putInt("error_count", currentCount + 1)
                putLong("last_error_time", System.currentTimeMillis())
            }.apply()
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error actualizando contador de errores", e)
        }
    }
    
    /**
     * Obtiene logs no sincronizados para enviar a Flutter/Hive
     */
    fun getUnsyncedLogs(context: Context): Map<String, Any> {
        try {
            if (dbHelper == null) initialize(context)
            
            val db = dbHelper?.readableDatabase
            val result = HashMap<String, Any>()
            
            // Obtener eventos no sincronizados
            val eventsCursor = db?.rawQuery("SELECT * FROM $TABLE_LOGS WHERE synced = 0 ORDER BY timestamp DESC LIMIT 100", null)
            val events = mutableListOf<HashMap<String, Any>>()
            
            eventsCursor?.use { cursor ->
                while (cursor.moveToNext()) {
                    val eventMap = HashMap<String, Any>()
                    eventMap["id"] = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                    eventMap["timestamp"] = cursor.getLong(cursor.getColumnIndexOrThrow("timestamp"))
                    eventMap["dateStr"] = cursor.getString(cursor.getColumnIndexOrThrow("date_str")) ?: ""
                    eventMap["eventType"] = cursor.getString(cursor.getColumnIndexOrThrow("event_type")) ?: ""
                    eventMap["data"] = cursor.getString(cursor.getColumnIndexOrThrow("data")) ?: ""
                    events.add(eventMap)
                }
            }
            
            // Obtener errores no sincronizados
            val errorsCursor = db?.rawQuery("SELECT * FROM $TABLE_ERRORS WHERE synced = 0 ORDER BY timestamp DESC LIMIT 50", null)
            val errors = mutableListOf<HashMap<String, Any>>()
            
            errorsCursor?.use { cursor ->
                while (cursor.moveToNext()) {
                    val errorMap = HashMap<String, Any>()
                    errorMap["id"] = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                    errorMap["timestamp"] = cursor.getLong(cursor.getColumnIndexOrThrow("timestamp"))
                    errorMap["dateStr"] = cursor.getString(cursor.getColumnIndexOrThrow("date_str")) ?: ""
                    errorMap["errorType"] = cursor.getString(cursor.getColumnIndexOrThrow("error_type")) ?: ""
                    errorMap["errorMessage"] = cursor.getString(cursor.getColumnIndexOrThrow("error_message")) ?: ""
                    errorMap["stackTrace"] = cursor.getString(cursor.getColumnIndexOrThrow("stack_trace")) ?: ""
                    errors.add(errorMap)
                }
            }
            
            // Obtener métricas no sincronizadas
            val metricsCursor = db?.rawQuery("SELECT * FROM $TABLE_METRICS WHERE synced = 0 ORDER BY timestamp DESC LIMIT 50", null)
            val metrics = mutableListOf<HashMap<String, Any>>()
            
            metricsCursor?.use { cursor ->
                while (cursor.moveToNext()) {
                    val metricMap = HashMap<String, Any>()
                    metricMap["id"] = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                    metricMap["timestamp"] = cursor.getLong(cursor.getColumnIndexOrThrow("timestamp"))
                    metricMap["dateStr"] = cursor.getString(cursor.getColumnIndexOrThrow("date_str")) ?: ""
                    metricMap["latitude"] = cursor.getDouble(cursor.getColumnIndexOrThrow("latitude"))
                    metricMap["longitude"] = cursor.getDouble(cursor.getColumnIndexOrThrow("longitude"))
                    metricMap["provider"] = cursor.getString(cursor.getColumnIndexOrThrow("provider")) ?: ""
                    metricMap["accuracy"] = cursor.getFloat(cursor.getColumnIndexOrThrow("accuracy")).toDouble()
                    metricMap["speed"] = cursor.getFloat(cursor.getColumnIndexOrThrow("speed")).toDouble()
                    metrics.add(metricMap)
                }
            }
            
            result["events"] = events
            result["errors"] = errors
            result["metrics"] = metrics
            
            Log.d(TAG, "📤 Logs no sincronizados: ${events.size} eventos, ${errors.size} errores, ${metrics.size} métricas")
            
            return result
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error obteniendo logs no sincronizados", e)
            return HashMap<String, Any>()
        }
    }
    
    /**
     * Marca logs como sincronizados
     */
    fun markLogsSynced(context: Context, eventIds: List<Int>, errorIds: List<Int>, metricIds: List<Int>) {
        try {
            if (dbHelper == null) initialize(context)
            
            val db = dbHelper?.writableDatabase
            
            // Marcar eventos como sincronizados
            if (eventIds.isNotEmpty()) {
                val placeholders = eventIds.joinToString(",") { "?" }
                db?.execSQL("UPDATE $TABLE_LOGS SET synced = 1 WHERE id IN ($placeholders)", eventIds.toTypedArray())
            }
            
            // Marcar errores como sincronizados
            if (errorIds.isNotEmpty()) {
                val placeholders = errorIds.joinToString(",") { "?" }
                db?.execSQL("UPDATE $TABLE_ERRORS SET synced = 1 WHERE id IN ($placeholders)", errorIds.toTypedArray())
            }
            
            // Marcar métricas como sincronizadas
            if (metricIds.isNotEmpty()) {
                val placeholders = metricIds.joinToString(",") { "?" }
                db?.execSQL("UPDATE $TABLE_METRICS SET synced = 1 WHERE id IN ($placeholders)", metricIds.toTypedArray())
            }
            
            Log.d(TAG, "✅ Logs marcados como sincronizados")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error marcando logs como sincronizados", e)
        }
    }
    
    /**
     * Limpia logs antiguos (más de 7 días)
     */
    fun cleanupOldLogs(context: Context) {
        try {
            if (dbHelper == null) initialize(context)
            
            val db = dbHelper?.writableDatabase
            val sevenDaysAgo = System.currentTimeMillis() - (7 * 24 * 60 * 60 * 1000)
            
            // Limpiar logs sincronizados más antiguos que 7 días
            db?.execSQL("DELETE FROM $TABLE_LOGS WHERE synced = 1 AND timestamp < ?", arrayOf(sevenDaysAgo))
            db?.execSQL("DELETE FROM $TABLE_ERRORS WHERE synced = 1 AND timestamp < ?", arrayOf(sevenDaysAgo))
            db?.execSQL("DELETE FROM $TABLE_METRICS WHERE synced = 1 AND timestamp < ?", arrayOf(sevenDaysAgo))
            
            // Limpiar archivos de log antiguos
            cleanupOldLogFiles(context)
            
            Log.d(TAG, "🧹 Logs antiguos limpiados")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error limpiando logs antiguos", e)
        }
    }
    
    /**
     * Limpia archivos de log antiguos
     */
    private fun cleanupOldLogFiles(context: Context) {
        try {
            val logDir = File(context.filesDir, "location_logs")
            if (!logDir.exists()) return
            
            val sevenDaysAgo = System.currentTimeMillis() - (7 * 24 * 60 * 60 * 1000)
            
            logDir.listFiles()?.forEach { file ->
                if (file.lastModified() < sevenDaysAgo) {
                    file.delete()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error limpiando archivos de log", e)
        }
    }
}

/**
 * Helper para la base de datos SQLite de logs
 */
class LocationLogDBHelper(context: Context) : SQLiteOpenHelper(context, LocationLogger.DB_NAME, null, LocationLogger.DB_VERSION) {
    
    override fun onCreate(db: SQLiteDatabase) {
        // Tabla de eventos/logs generales
        db.execSQL("""
            CREATE TABLE location_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                date_str TEXT NOT NULL,
                event_type TEXT NOT NULL,
                data TEXT,
                synced INTEGER DEFAULT 0
            )
        """)
        
        // Tabla de errores
        db.execSQL("""
            CREATE TABLE location_errors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                date_str TEXT NOT NULL,
                error_type TEXT NOT NULL,
                error_message TEXT NOT NULL,
                stack_trace TEXT,
                synced INTEGER DEFAULT 0
            )
        """)
        
        // Tabla de métricas de ubicación
        db.execSQL("""
            CREATE TABLE location_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                date_str TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                provider TEXT NOT NULL,
                accuracy REAL,
                speed REAL,
                synced INTEGER DEFAULT 0
            )
        """)
        
        // Índices para mejorar rendimiento
        db.execSQL("CREATE INDEX idx_logs_timestamp ON location_logs(timestamp)")
        db.execSQL("CREATE INDEX idx_logs_synced ON location_logs(synced)")
        db.execSQL("CREATE INDEX idx_errors_timestamp ON location_errors(timestamp)")
        db.execSQL("CREATE INDEX idx_errors_synced ON location_errors(synced)")
        db.execSQL("CREATE INDEX idx_metrics_timestamp ON location_metrics(timestamp)")
        db.execSQL("CREATE INDEX idx_metrics_synced ON location_metrics(synced)")
    }
    
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Por ahora, recrear las tablas en caso de upgrade
        db.execSQL("DROP TABLE IF EXISTS location_logs")
        db.execSQL("DROP TABLE IF EXISTS location_errors")
        db.execSQL("DROP TABLE IF EXISTS location_metrics")
        onCreate(db)
    }
}