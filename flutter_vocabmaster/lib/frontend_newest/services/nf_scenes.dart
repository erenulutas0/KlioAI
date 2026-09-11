import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';

/// A situation the tutor plays instead of being itself.
///
/// The backend has had roleplay prompts since long before this tab existed,
/// reached through a `scenario` argument that only the retired chat screen ever
/// filled in. Everything worked except the part a learner could touch: the
/// server knew how to be a barista and the app never asked it to.
///
/// The scenes come from the server's catalog now (see [NfSceneCatalog]): a
/// title and a goal in the learner's language, a character with its own voice,
/// and several ways to open. The eight in [all] are the ones this app shipped
/// with, kept so the rail is never empty -- offline, or before the catalog has
/// ever loaded. [character] has to match the name in the server's catalog: the
/// header shows it, and a learner reading "Amy" while the voice says "I am
/// Emma" is being told the app does not know who is talking.
class NfScene {
  const NfScene({
    required this.id,
    required this.character,
    required this.opening,
    required this.icon,
    this.openings = const <String>[],
    this.category = 'daily',
    this.goal,
    this.voice,
    this.minLevel,
    this.title,
  });

  /// Matches the scenario id the backend switches on. Not a display string.
  final String id;
  final String character;

  /// What the scene opens with when it has only one way to, or the variant is
  /// unknown. Written into the app rather than fetched for the built-in
  /// scenes, for the same reason the plain greeting is: choosing a scene should
  /// not spend a request from someone's daily quota before they have said a word.
  final String opening;
  final IconData icon;

  /// Every way the scene can open. Which one a conversation gets is
  /// [openingFor] its variant -- the same pick the server makes, so the model
  /// is told the line the learner actually saw.
  final List<String> openings;

  /// daily, travel, social, work, health or problems: how the picker groups it.
  final String category;

  /// What the learner is in the scene to do, in their language. Null for a
  /// built-in scene until the catalog has loaded.
  final String? goal;

  /// The Piper voice the character speaks in. Null speaks in the tutor's.
  final String? voice;

  /// The lowest level the scene is written for, as CEFR.
  final String? minLevel;

  /// The scene's name in the learner's language, from the catalog. Null reads
  /// it from the app's own translations.
  final String? title;

  /// What the tutor opens with when no scene is chosen.
  ///
  /// English, like every [opening] below it, and for a reason that took a
  /// phone to see. This line used to be translated, so a Turkish learner was
  /// greeted with "Selam, ben Ryan" — and then Piper read that Turkish
  /// sentence with an English voice, which sounds exactly like a foreigner
  /// struggling through Turkish. The tutor is the one thing in this app that
  /// must never do that: it is here to be a native speaker.
  ///
  /// The interface around it stays translated. The caption under the button
  /// still reads "Konuşmak için basılı tut", so the instruction is available
  /// in the learner's own language without the tutor breaking character.
  static const String freeChatOpening =
      "Hi, I'm {name}. Hold the button below and tell me about your day — "
      "I'll answer out loud.";

  /// The scene's name in the learner's own language.
  String nameOf(BuildContext context) => title ?? context.tr('tutor.scene.$id');

  /// The opening a conversation dealt [variant] gets: the variant modulo the
  /// count, which is what the server's ScenarioCatalog.openingFor computes.
  String openingFor(int? variant) {
    if (variant == null || openings.isEmpty) {
      return opening;
    }
    return openings[variant % openings.length];
  }

  /// Everyday scenes first. The four that already existed are all office and
  /// lecture hall, and the person who needs those is not the person who most
  /// needs this feature.
  static const List<NfScene> all = <NfScene>[
    NfScene(
      id: 'cafe_order',
      character: 'Emma',
      opening: 'Hi there! What can I get started for you?',
      icon: Icons.local_cafe_outlined,
      voice: 'lessac',
    ),
    NfScene(
      id: 'airport_checkin',
      character: 'Mark',
      opening:
          'Good morning. Passport, please — and where are you flying to today?',
      icon: Icons.flight_takeoff_outlined,
      category: 'travel',
      voice: 'ryan',
    ),
    NfScene(
      id: 'hotel_checkin',
      character: 'Nina',
      opening: 'Welcome! Could I have your booking name and some ID?',
      icon: Icons.hotel_outlined,
      category: 'travel',
      voice: 'jenny_dioco',
    ),
    NfScene(
      id: 'small_talk',
      character: 'Alex',
      opening:
          'I do not think we have met — I am Alex. How do you know the host?',
      icon: Icons.waving_hand_outlined,
      category: 'social',
      voice: 'alan',
    ),
    NfScene(
      id: 'doctor_visit',
      character: 'Dr. Patel',
      opening: 'Come in, have a seat. So, what has been bothering you?',
      icon: Icons.medical_services_outlined,
      category: 'health',
      voice: 'cori',
    ),
    NfScene(
      id: 'shopping_return',
      character: 'Sam',
      opening: 'Hello! What seems to be the problem with it?',
      icon: Icons.shopping_bag_outlined,
      category: 'problems',
      voice: 'ryan',
    ),
    NfScene(
      id: 'job_interview_followup',
      character: 'Sarah',
      opening: 'Thanks for calling back. How are you feeling about the role?',
      icon: Icons.business_center_outlined,
      category: 'work',
      voice: 'lessac',
    ),
    NfScene(
      id: 'academic_presentation_qa',
      character: 'Dr. Johnson',
      opening:
          'Thank you for the presentation. I have a few questions about your method.',
      icon: Icons.school_outlined,
      category: 'work',
      voice: 'alan',
    ),
  ];

  /// One catalog entry, or null if it lacks what a scene needs to start: an
  /// id to send, a character to name and something to open with.
  static NfScene? fromCatalog(Object? value) {
    if (value is! Map) {
      return null;
    }
    String? text(String key) {
      final Object? v = value[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final Object? rawOpenings = value['openings'];
    final List<String> openings = <String>[
      if (rawOpenings is List)
        for (final Object? o in rawOpenings)
          if (o is String && o.trim().isNotEmpty) o.trim(),
    ];
    final String? id = text('id');
    final String? character = text('character');
    if (id == null || character == null || openings.isEmpty) {
      return null;
    }
    return NfScene(
      id: id,
      character: character,
      opening: openings.first,
      openings: openings,
      icon: _sceneIcons[text('icon')] ?? Icons.theater_comedy_outlined,
      category: text('category') ?? 'daily',
      goal: text('goal'),
      voice: text('voice'),
      minLevel: text('minLevel'),
      title: text('title'),
    );
  }
}

/// The icons a catalog entry may name. A name not here draws the default mask
/// rather than nothing: a new scene added on the server needs no app release
/// to appear, only to get its own picture.
const Map<String, IconData> _sceneIcons = <String, IconData>{
  'local_cafe': Icons.local_cafe_outlined,
  'restaurant': Icons.restaurant_outlined,
  'shopping_cart': Icons.shopping_cart_outlined,
  'content_cut': Icons.content_cut_outlined,
  'flight_takeoff': Icons.flight_takeoff_outlined,
  'badge': Icons.badge_outlined,
  'hotel': Icons.hotel_outlined,
  'local_taxi': Icons.local_taxi_outlined,
  'directions': Icons.directions_outlined,
  'luggage': Icons.luggage_outlined,
  'train': Icons.train_outlined,
  'waving_hand': Icons.waving_hand_outlined,
  'event': Icons.event_outlined,
  'home': Icons.home_outlined,
  'work': Icons.work_outline,
  'business_center': Icons.business_center_outlined,
  'groups': Icons.groups_outlined,
  'record_voice_over': Icons.record_voice_over_outlined,
  'forum': Icons.forum_outlined,
  'school': Icons.school_outlined,
  'medical_services': Icons.medical_services_outlined,
  'local_pharmacy': Icons.local_pharmacy_outlined,
  'shopping_bag': Icons.shopping_bag_outlined,
  'build': Icons.build_outlined,
  'credit_card': Icons.credit_card_outlined,
};

/// The scenes the server offers, and the last copy of them on this device.
///
/// Kept per language: the titles and goals are written in the learner's, and
/// a Turkish copy shown to someone who has just switched the app to German
/// would be the wrong language on the one card meant to orient them.
class NfSceneCatalog {
  const NfSceneCatalog._();

  static const String _prefsPrefix = 'nf_scene_catalog_v1_';

  /// Every playable scene in [body], in the server's order; null if [body] is
  /// not a catalog or holds no scene that can start.
  static List<NfScene>? parse(Object? body) {
    if (body is! Map) {
      return null;
    }
    final Object? entries = body['scenes'];
    if (entries is! List) {
      return null;
    }
    final List<NfScene> scenes = <NfScene>[
      for (final Object? entry in entries)
        if (NfScene.fromCatalog(entry) case final NfScene scene) scene,
    ];
    return scenes.isEmpty ? null : scenes;
  }

  /// What was last fetched in [language], or null.
  static Future<List<NfScene>?> cached(String language) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString('$_prefsPrefix$language');
      return raw == null ? null : parse(jsonDecode(raw));
    } catch (error) {
      debugPrint('NfSceneCatalog cache read failed: $error');
      return null;
    }
  }

  /// A fresh copy from the server, kept for next time; null if none could be
  /// had. Nothing waits on this: the rail shows what it already has meanwhile.
  static Future<List<NfScene>?> refresh(ApiService api, String language) async {
    try {
      final Map<String, dynamic> body = await api.chatbotScenarios(language);
      final List<NfScene>? scenes = parse(body);
      if (scenes == null) {
        return null;
      }
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsPrefix$language', jsonEncode(body));
      return scenes;
    } catch (error) {
      debugPrint('NfSceneCatalog refresh failed: $error');
      return null;
    }
  }
}
