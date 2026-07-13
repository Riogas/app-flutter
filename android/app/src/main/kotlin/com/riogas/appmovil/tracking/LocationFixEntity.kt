package com.riogas.appmovil.tracking

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "location_fixes")
data class LocationFixEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val movil: Int,
    val escenario: Int,
    val usuario: String,
    val deviceId: String,
    val latitud: Double,
    val longitud: Double,
    val accuracy: Float,
    val fechaHora: String, // ISO local, mismo formato que hoy manda LocationHelper
    val createdAt: Long,
    // Campos adicionales del fix, agregados en la iteración 2 (fix de review) para poder
    // reproducir el body IDÉNTICO que LocationHelper.kt manda hoy a track/RioGas. No
    // capturados por Task 5 (eso es de quien inserte el fix, ej. Task 6); van con default
    // razonable para no romper compilación de código existente.
    val utmX: Double = 0.0,
    val utmY: Double = 0.0,
    val distanciaRecorrida: Float = 0f,
    val velocidad: Float = 0f,
    val altitude: Double? = null,
    val bearing: Float? = null,
    val provider: String = "",
    val speedAccuracy: Float? = null,
    val isMockLocation: Boolean = false,
    val movementType: String = "DESCONOCIDO", // mismo default que LocationHelper.kt:1439
    val executionCounter: Int = 0,
    val sentRioGas: Boolean = false,
    val sentTrack: Boolean = false,
    val attempts: Int = 0
)
