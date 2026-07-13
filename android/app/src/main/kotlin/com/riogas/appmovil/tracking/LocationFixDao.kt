package com.riogas.appmovil.tracking

import androidx.room.*

@Dao
interface LocationFixDao {
    @Insert
    suspend fun insert(fix: LocationFixEntity): Long

    @Query("SELECT * FROM location_fixes WHERE sentTrack = 0 ORDER BY id ASC LIMIT :limit")
    suspend fun getUnsentTrack(limit: Int): List<LocationFixEntity>

    @Query("SELECT * FROM location_fixes WHERE sentRioGas = 0 ORDER BY id ASC LIMIT :limit")
    suspend fun getUnsentRioGas(limit: Int): List<LocationFixEntity>

    @Query("UPDATE location_fixes SET sentTrack = 1 WHERE id IN (:ids)")
    suspend fun markTrackSent(ids: List<Long>)

    @Query("UPDATE location_fixes SET sentRioGas = 1 WHERE id IN (:ids)")
    suspend fun markRioGasSent(ids: List<Long>)

    @Query("UPDATE location_fixes SET attempts = attempts + 1 WHERE id IN (:ids)")
    suspend fun incrementAttempts(ids: List<Long>)

    @Query("DELETE FROM location_fixes WHERE sentTrack = 1 AND sentRioGas = 1 AND createdAt < :olderThan")
    suspend fun purgeSent(olderThan: Long)

    // Retención dura independiente del estado de envío: cubre el caso gpsN8nEnabled=false
    // (flushTrack no marca sentTrack y purgeSent nunca borra esas filas) para acotar el
    // crecimiento de tracking.db pase lo que pase.
    @Query("DELETE FROM location_fixes WHERE createdAt < :olderThan")
    suspend fun purgeOlderThan(olderThan: Long)

    @Query("SELECT COUNT(*) FROM location_fixes WHERE sentTrack = 0 OR sentRioGas = 0")
    suspend fun countUnsent(): Int
}
