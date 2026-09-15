package com.example.flutter_vocabmaster

import android.app.Activity
import android.app.Application
import android.app.PendingIntent
import android.content.Intent
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter

/**
 * Google's billing and sign-in activities, started the way the device farm started them: by
 * name, with an empty intent -- on Android 11, as the farm's phones were, and on Android 9, where
 * the guard has no pre-create callback and repairs the intent from inside super.onCreate().
 *
 * The first two tests are the crash as Crashlytics reported it, against the real library classes
 * this app ships. They are here so that a library upgrade which changes either activity fails
 * a test instead of quietly making the guard pointless or wrong.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 30])
class PlayActivityLaunchGuardTest {

    private val app: Application = RuntimeEnvironment.getApplication()

    @After
    fun unregister() {
        app.unregisterActivityLifecycleCallbacks(PlayActivityLaunchGuard)
    }

    @Suppress("UNCHECKED_CAST")
    private fun activityClass(name: String) = Class.forName(name) as Class<out Activity>

    private fun assertNullPointerIn(block: () -> Unit) {
        try {
            block()
        } catch (thrown: Throwable) {
            var cause: Throwable? = thrown
            while (cause != null) {
                if (cause is NullPointerException) return
                cause = cause.cause
            }
            throw AssertionError("expected a NullPointerException, got $thrown", thrown)
        }
        fail("the activity started without crashing, so the library no longer behaves as the guard assumes")
    }

    @Test
    fun aBareBillingLaunchIsTheCrashCrashlyticsReported() {
        assertNullPointerIn {
            Robolectric.buildActivity(activityClass(PlayActivityLaunchGuard.BILLING_ACTIVITY), Intent()).create()
        }
    }

    @Test
    fun aBareSignInLaunchIsTheCrashCrashlyticsReported() {
        assertNullPointerIn {
            Robolectric.buildActivity(activityClass(PlayActivityLaunchGuard.SIGN_IN_ACTIVITY), Intent()).create()
        }
    }

    @Test
    fun withTheGuardABareBillingLaunchClosesInstead() {
        app.registerActivityLifecycleCallbacks(PlayActivityLaunchGuard)

        val activity = Robolectric
            .buildActivity(activityClass(PlayActivityLaunchGuard.BILLING_ACTIVITY), Intent())
            .create()
            .get()

        // It asked for the empty answer...
        val request = shadowOf(activity).lastIntentSenderRequest
        assertNotNull("the billing screen did not start the empty answer", request)
        assertEquals(100, request.requestCode)

        // ...and closes when it comes back, as it does when a learner cancels a purchase.
        ReflectionHelpers.callInstanceMethod<Unit>(
            activity,
            "onActivityResult",
            ClassParameter.from(Int::class.javaPrimitiveType, 100),
            ClassParameter.from(Int::class.javaPrimitiveType, Activity.RESULT_CANCELED),
            ClassParameter.from(Intent::class.java, null),
        )
        assertTrue(activity.isFinishing)
    }

    @Test
    fun withTheGuardABareSignInLaunchClosesInstead() {
        app.registerActivityLifecycleCallbacks(PlayActivityLaunchGuard)

        val activity = Robolectric
            .buildActivity(activityClass(PlayActivityLaunchGuard.SIGN_IN_ACTIVITY), Intent())
            .create()
            .get()

        assertTrue(activity.isFinishing)
    }

    @Test
    fun aPurchaseTheBillingLibraryStartsIsLeftAlone() {
        app.registerActivityLifecycleCallbacks(PlayActivityLaunchGuard)
        val playStoreSheet = PendingIntent.getActivity(
            app, 7, Intent("com.android.vending.billing.PURCHASE"), PendingIntent.FLAG_IMMUTABLE,
        )

        val activity = Robolectric
            .buildActivity(
                activityClass(PlayActivityLaunchGuard.BILLING_ACTIVITY),
                Intent().putExtra("BUY_INTENT", playStoreSheet),
            )
            .create()
            .get()

        @Suppress("DEPRECATION")
        assertSame(playStoreSheet, activity.intent.getParcelableExtra<PendingIntent>("BUY_INTENT"))
        assertEquals(playStoreSheet.intentSender, shadowOf(activity).lastIntentSenderRequest.intentSender)
    }

    @Test
    fun theEmptyAnswerIsACancel() {
        val activity = Robolectric.buildActivity(EmptyLaunchActivity::class.java).create().get()

        assertEquals(Activity.RESULT_CANCELED, shadowOf(activity).resultCode)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun onlyTheLaunchesNeitherLibraryCanMakeAreRepaired() {
        val billing = PlayActivityLaunchGuard.BILLING_ACTIVITY
        val signIn = PlayActivityLaunchGuard.SIGN_IN_ACTIVITY
        val none = PlayActivityLaunchGuard.Repair.NONE

        assertEquals(
            PlayActivityLaunchGuard.Repair.BILLING_EMPTY_RESULT,
            PlayActivityLaunchGuard.repairFor(billing, null, hasExtras = false, restored = false),
        )
        assertEquals(
            PlayActivityLaunchGuard.Repair.SIGN_IN_ACTION,
            PlayActivityLaunchGuard.repairFor(signIn, null, hasExtras = false, restored = false),
        )
        // Anything carrying extras, even under a key this code does not know.
        assertEquals(none, PlayActivityLaunchGuard.repairFor(billing, null, hasExtras = true, restored = false))
        // Restored after the process died: the library never reads the intent on that path.
        assertEquals(none, PlayActivityLaunchGuard.repairFor(billing, null, hasExtras = false, restored = true))
        assertEquals(
            none,
            PlayActivityLaunchGuard.repairFor(signIn, "com.google.android.gms.auth.GOOGLE_SIGN_IN", hasExtras = true, restored = false),
        )
        assertEquals(
            none,
            PlayActivityLaunchGuard.repairFor("com.example.flutter_vocabmaster.MainActivity", null, hasExtras = false, restored = false),
        )
    }
}
