package com.example.flutter_vocabmaster

import android.app.Application

/** The default Application, plus [PlayActivityLaunchGuard], registered before any activity. */
class KlioApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(PlayActivityLaunchGuard)
    }
}
