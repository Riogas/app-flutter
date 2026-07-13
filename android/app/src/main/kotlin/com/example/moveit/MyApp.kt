package com.example.moveit

import android.app.Application
import android.os.Build
import io.flutter.FlutterInjector

class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()

        val args = mutableListOf<String>()

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            println("⚠️ Android < 8 → activando software rendering y desactivando Impeller")
            args.add("--enable-software-rendering")
            args.add("--disable-impeller")
        } else {
            println("✅ Android >= 8 → usando Impeller")
            args.add("--enable-impeller")
        }

        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(this)
        loader.ensureInitializationComplete(this, args.toTypedArray())
    }
}
