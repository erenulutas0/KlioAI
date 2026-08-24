import 'package:flutter/widgets.dart';

/// The app's one navigator, reachable from code that has no `BuildContext`.
///
/// Used by the session-expiry handler in `main.dart` and by
/// `LocalReminderService` when a notification is tapped.
///
/// It lived inside `widgets/theme_side_tab.dart` until the theme drawer was
/// taken out of the app — which meant every file that needed the navigator
/// imported a UI widget to get at it, and unmounting that widget would have
/// looked like it broke notification routing.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
