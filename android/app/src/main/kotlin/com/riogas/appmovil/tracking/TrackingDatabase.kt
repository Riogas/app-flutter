package com.riogas.appmovil.tracking

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [LocationFixEntity::class], version = 1, exportSchema = false)
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
