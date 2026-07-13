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
    val sentRioGas: Boolean = false,
    val sentTrack: Boolean = false,
    val attempts: Int = 0
)
