package com.riogas.appmovil.tracking

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

// v2 (iteración 2, fix de review): se agregaron columnas de contexto del fix a
// LocationFixEntity (utmX/utmY/distanciaRecorrida/velocidad/altitude/bearing/provider/
// speedAccuracy/isMockLocation/movementType/executionCounter) para poder armar el body
// IDÉNTICO al que LocationHelper.kt manda hoy. fallbackToDestructiveMigration cubre el
// upgrade (no hay datos en producción todavía, la cola no está cableada aún).
@Database(entities = [LocationFixEntity::class], version = 2, exportSchema = false)
abstract class TrackingDatabase : RoomDatabase() {
    abstract fun locationFixDao(): LocationFixDao

    companion object {
        @Volatile private var INSTANCE: TrackingDatabase? = null
        fun get(context: Context): TrackingDatabase =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext, TrackingDatabase::class.java, "tracking.db"
                ).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
    }
}
