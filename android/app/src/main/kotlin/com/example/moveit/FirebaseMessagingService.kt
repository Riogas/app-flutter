package com.example.moveit

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        Log.d("🔥FCM", "📩 Notificación recibida")

        // Si la notificación tiene datos
        remoteMessage.data.isNotEmpty().let {
            Log.d("🔥FCM", "Datos: ${remoteMessage.data}")
        }

        // Si la notificación tiene contenido de notificación (título, cuerpo, etc.)
        remoteMessage.notification?.let {
            Log.d("🔥FCM", "Título: ${it.title}")
            Log.d("🔥FCM", "Cuerpo: ${it.body}")
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("🔥FCM", "Nuevo token generado: $token")
        // Aquí podrías enviarlo a tu backend si lo necesitas
    }
}
