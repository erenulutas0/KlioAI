package com.example.flutter_vocabmaster

import android.app.Activity
import android.os.Bundle

/**
 * Answers the billing screen when it was started with nothing to show, so it closes instead of
 * crashing. See [PlayActivityLaunchGuard].
 */
class EmptyLaunchActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        finish()
    }
}
