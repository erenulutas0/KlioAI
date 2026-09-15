package com.example.flutter_vocabmaster

import android.app.Activity
import android.app.Application
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Bundle

/**
 * Two activities the Play libraries add to this app's manifest, started by something other than
 * those libraries.
 *
 * Crashlytics for builds 463, 475 and 483: ProxyBillingActivity and SignInHubActivity throwing a
 * NullPointerException in onCreate, less than a second into a session, on OnePlus and Huawei
 * phones all running Android 11, a day or two after each of those builds reached Play and on no
 * other device. A learner cannot get there. ProxyBillingActivity (billing 8.0.0) reads its
 * PendingIntent only on a fresh start carrying neither BUY_INTENT nor IN_APP_MESSAGE_INTENT, and
 * the billing library never starts it without one; a restored activity takes the
 * savedInstanceState branch and never reads it. SignInHubActivity (play-services-auth 21.0.0)
 * dereferences its action, which the sign-in client always sets. What starts them bare is a tool
 * opening every activity in a manifest by name, and each of its devices counted as a crashed
 * user. Two earlier fixes -- the task affinity, and turning Test Lab devices off from Dart --
 * could not reach this: a launch like that never starts the Flutter side at all.
 *
 * So the one launch neither library can make is given something each already handles. The
 * sign-in screen gets an action it does not know, and logs and finishes. The billing screen gets
 * a PendingIntent to [EmptyLaunchActivity], which returns at once, so the library reports an
 * internal error to a purchase listener that is not there and finishes. Every launch the
 * libraries make themselves is left exactly as it was.
 */
object PlayActivityLaunchGuard : Application.ActivityLifecycleCallbacks {

    const val BILLING_ACTIVITY = "com.android.billingclient.api.ProxyBillingActivity"
    const val SIGN_IN_ACTIVITY = "com.google.android.gms.auth.api.signin.internal.SignInHubActivity"

    /** Not one of the actions SignInHubActivity accepts, which is the point. */
    const val UNKNOWN_SIGN_IN_ACTION = "klioai.EMPTY_LAUNCH"

    private const val BUY_INTENT = "BUY_INTENT"

    enum class Repair { NONE, SIGN_IN_ACTION, BILLING_EMPTY_RESULT }

    /** The decision on its own, so it can be pinned without an activity. */
    fun repairFor(
        activityClass: String,
        action: String?,
        hasExtras: Boolean,
        restored: Boolean,
    ): Repair = when {
        activityClass == SIGN_IN_ACTIVITY && action == null -> Repair.SIGN_IN_ACTION
        // No extras at all, not merely no BUY_INTENT: every launch the billing library makes
        // carries its PendingIntent under some key, so this cannot replace one of them even if a
        // later version adds a key this code has never heard of.
        activityClass == BILLING_ACTIVITY && !restored && !hasExtras -> Repair.BILLING_EMPTY_RESULT
        else -> Repair.NONE
    }

    // Before onCreate on Android 10 and later.
    override fun onActivityPreCreated(activity: Activity, savedInstanceState: Bundle?) {
        repair(activity, savedInstanceState)
    }

    // Earlier versions have no pre-create callback. This one runs inside Activity.onCreate, and
    // both activities call super.onCreate() before they read their intent.
    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            repair(activity, savedInstanceState)
        }
    }

    private fun repair(activity: Activity, savedInstanceState: Bundle?) {
        val intent = activity.intent ?: Intent()
        val extras = intent.extras
        when (repairFor(
            activity.javaClass.name,
            intent.action,
            hasExtras = extras != null && !extras.isEmpty,
            restored = savedInstanceState != null,
        )) {
            Repair.SIGN_IN_ACTION ->
                activity.intent = Intent(intent).setAction(UNKNOWN_SIGN_IN_ACTION)
            Repair.BILLING_EMPTY_RESULT ->
                activity.intent = Intent(intent).putExtra(
                    BUY_INTENT,
                    PendingIntent.getActivity(
                        activity,
                        0,
                        Intent(activity, EmptyLaunchActivity::class.java),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    ),
                )
            Repair.NONE -> Unit
        }
    }

    override fun onActivityStarted(activity: Activity) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit
}
