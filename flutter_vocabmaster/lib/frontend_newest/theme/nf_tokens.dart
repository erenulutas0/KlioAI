import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'nf_theme.dart';

/// Design tokens for the "Modern Oyunlu" frontend that lives under
/// `lib/frontend_newest/`.
///
/// This file is the single source of truth for colour, type, spacing and shape
/// in the new frontend: no other file under `lib/frontend_newest/` may declare a
/// raw [Color]. The private constructor is deliberate — the only two palettes
/// that exist are [NfTokens.light] and [NfTokens.dark], so a screen cannot
/// quietly invent a third one.
@immutable
class NfTokens {
  const NfTokens._({
    required this.brightness,
    required this.ground,
    required this.surface,
    required this.raised,
    required this.border,
    required this.borderStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.primary,
    required this.primaryInk,
    required this.primaryShadow,
    required this.primarySoft,
    required this.primaryText,
    required this.correct,
    required this.correctSoft,
    required this.wrong,
    required this.wrongSoft,
    required this.streak,
    required this.streakSoft,
    required this.streakText,
  });

  /// Which palette this instance is. Widgets should branch on tokens rather
  /// than on this, but a few effects (image overlays, system chrome) need it.
  final Brightness brightness;

  /// The page behind everything.
  final Color ground;

  /// Cards, sheets and anything that sits on [ground].
  final Color surface;

  /// One step up from [surface]: inner tiles, progress tracks, quiet fills.
  final Color raised;

  /// The 2px outline that is the signature of this direction.
  final Color border;

  /// A slightly heavier outline, and the offset shadow under secondary buttons.
  final Color borderStrong;

  /// Primary reading colour.
  final Color ink;

  /// Secondary / supporting copy.
  final Color inkMuted;

  /// Tertiary copy, placeholders, disabled labels.
  final Color inkFaint;

  /// Brand fill: primary buttons, selected states, progress fills.
  final Color primary;

  /// Text and icons drawn on top of [primary].
  final Color primaryInk;

  /// The solid, un-blurred slab under a primary button (0 4px 0).
  final Color primaryShadow;

  /// Brand tint used as a background (selected chips, primary-flavoured tiles).
  final Color primarySoft;

  /// Brand colour for text/links sitting directly on [ground] or [surface].
  /// Distinct from [primary] because a fill colour and a text colour need
  /// different contrast in dark mode.
  final Color primaryText;

  /// Correct answer / positive result.
  final Color correct;

  /// Background tint for a correct state.
  final Color correctSoft;

  /// Wrong answer / destructive.
  final Color wrong;

  /// Background tint for a wrong state.
  final Color wrongSoft;

  /// Streak flame / daily-goal accent. Identical in both themes on purpose.
  final Color streak;

  /// Background tint for a streak state.
  final Color streakSoft;

  /// Streak colour that is legible as text (raw [streak] is too light on white).
  final Color streakText;

  /// Fully transparent. Exists so that widgets never need `Colors.transparent`
  /// and the "no colour outside this file" rule stays literally true.
  static const Color transparent = Color(0x00000000);

  static const NfTokens light = NfTokens._(
    brightness: Brightness.light,
    ground: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF6F5FB),
    border: Color(0xFFEEECF6),
    borderStrong: Color(0xFFE9E7F2),
    ink: Color(0xFF232033),
    inkMuted: Color(0xFF7A7690),
    inkFaint: Color(0xFFA5A1B8),
    primary: Color(0xFF6C4EF5),
    primaryInk: Color(0xFFFFFFFF),
    primaryShadow: Color(0xFF5138CC),
    primarySoft: Color(0xFFEFEAFE),
    primaryText: Color(0xFF6C4EF5),
    correct: Color(0xFF34B36F),
    correctSoft: Color(0xFFE4F7EC),
    wrong: Color(0xFFE85B5B),
    wrongSoft: Color(0xFFFDEAEA),
    streak: Color(0xFFFFB020),
    streakSoft: Color(0xFFFFF4DC),
    streakText: Color(0xFFC98508),
  );

  static const NfTokens dark = NfTokens._(
    brightness: Brightness.dark,
    ground: Color(0xFF131120),
    surface: Color(0xFF1B1830),
    raised: Color(0xFF232040),
    border: Color(0xFF2B2745),
    borderStrong: Color(0xFF2A2648),
    ink: Color(0xFFF1EFFA),
    inkMuted: Color(0xFF9C97B8),
    inkFaint: Color(0xFF6B6690),
    primary: Color(0xFF7C61FB),
    primaryInk: Color(0xFFFFFFFF),
    primaryShadow: Color(0xFF4D35C9),
    // rgba(139, 113, 255, 0.16)
    primarySoft: Color.fromRGBO(139, 113, 255, 0.16),
    primaryText: Color(0xFFA18CFF),
    correct: Color(0xFF5CD996),
    // rgba(74, 222, 140, 0.13)
    correctSoft: Color.fromRGBO(74, 222, 140, 0.13),
    wrong: Color(0xFFF07A7A),
    wrongSoft: Color(0xFF251723),
    streak: Color(0xFFFFB020),
    // rgba(255, 176, 32, 0.14)
    streakSoft: Color.fromRGBO(255, 176, 32, 0.14),
    streakText: Color(0xFFFFC554),
  );

  bool get isDark => brightness == Brightness.dark;

  /// The palette for a given [brightness].
  static NfTokens resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The palette in scope.
  ///
  /// Falls back to the platform brightness when no [NfTheme] ancestor is found.
  /// That happens for routes and dialogs pushed above the widget that installs
  /// [NfTheme]; falling back beats throwing, and the caller still gets a
  /// coherent palette.
  static NfTokens of(BuildContext context) =>
      NfTheme.maybeOf(context) ??
      resolve(MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light);

  // --------------------------------------------------------------------------
  // Derived colour helpers. These only ever combine tokens declared above.
  // --------------------------------------------------------------------------

  /// The standard 2px outline.
  BorderSide get side => BorderSide(color: border, width: NfStroke.border);

  /// The heavier 2px outline, for elements that must separate from a tinted
  /// background.
  BorderSide get sideStrong =>
      BorderSide(color: borderStrong, width: NfStroke.border);

  /// A 2px outline in an arbitrary token colour (semantic cards, chips).
  BorderSide sideOf(Color color) =>
      BorderSide(color: color, width: NfStroke.border);

  /// The signature drop: solid, offset, zero blur. Used by anything that wants
  /// the pushable look without the press behaviour of `NfPrimaryButton`.
  static List<BoxShadow> solidShadow(
    Color color, {
    double depth = NfSize.pressDepth,
  }) =>
      <BoxShadow>[
        BoxShadow(color: color, offset: Offset(0, depth)),
      ];

  // --------------------------------------------------------------------------
  // Type. `display` is Fredoka (headings, numbers, button labels), `body` is
  // Nunito (everything else). Leave [color] null to inherit from the ambient
  // DefaultTextStyle.
  // --------------------------------------------------------------------------

  static const FontWeight displayWeight = FontWeight.w600;
  static const FontWeight bodyWeight = FontWeight.w700;
  static const FontWeight bodyEmphasisWeight = FontWeight.w800;

  static TextStyle display({
    double size = NfFont.s20,
    FontWeight weight = displayWeight,
    Color? color,
    double height = 1.15,
    double? letterSpacing,
    TextDecoration? decoration,
  }) {
    return GoogleFonts.baloo2(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
    ).copyWith(fontFamilyFallback: _turkishFallback);
  }

  /// Display type is Baloo 2 because Fredoka cannot draw s-cedilla, and every
  /// other Turkish sentence has one.
  ///
  /// On a real phone the home screen greeted people with "Hos,geldin" -- the
  /// cedilla detached from its letter and sitting in the following space. The
  /// same word one line below, set in body type, was perfect, and both come
  /// from the same correctly spelled string: that is what identified the face
  /// rather than the text. Adding a fallback family fixed nothing, which is
  /// itself the diagnosis -- Fredoka does carry a combining cedilla, so no
  /// glyph was ever missing for a fallback to supply; what it lacks is the
  /// anchor that would attach the mark to the s. Only changing the face helps.
  ///
  /// The fallback stays anyway, for whatever Baloo 2 turns out not to have.
  /// The family name is read from the package rather than written out, so it
  /// cannot drift out of step with what body() actually loads.
  static final List<String> _turkishFallback = <String>[
    GoogleFonts.nunito().fontFamily ?? 'Nunito',
  ];

  static TextStyle body({
    double size = NfFont.s14,
    FontWeight weight = bodyWeight,
    Color? color,
    double height = 1.35,
    double? letterSpacing,
    TextDecoration? decoration,
  }) {
    return GoogleFonts.nunito(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
    );
  }
}

/// The only font sizes the new frontend uses. Named after the value so a
/// reviewer can check a screen against the spec at a glance.
class NfFont {
  NfFont._();

  static const double s25 = 25;
  static const double s23 = 23;
  static const double s22 = 22;
  static const double s20 = 20;
  static const double s18 = 18;
  static const double s17 = 17;
  static const double s16 = 16;
  static const double s15 = 15;
  static const double s145 = 14.5;
  static const double s14 = 14;
  static const double s135 = 13.5;
  static const double s13 = 13;
  static const double s125 = 12.5;
  static const double s12 = 12;
  static const double s115 = 11.5;
  static const double s105 = 10.5;
}

/// The spacing scale. Gaps and paddings come from here, nowhere else.
class NfSpace {
  NfSpace._();

  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s22 = 22;
  static const double s26 = 26;

  /// Default inner padding of an [NfCard].
  static const EdgeInsets cardPadding = EdgeInsets.all(s16);

  /// Default horizontal page gutter.
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: s16);
}

/// Corner radii.
class NfRadius {
  NfRadius._();

  static const double card = 20;
  static const double control = 16;
  static const double tile = 12;
  static const double iconTile = 12;

  /// Effectively a pill; large enough that Flutter clamps it to half the height.
  static const double pill = 999;

  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius controlAll =
      BorderRadius.all(Radius.circular(control));
  static const BorderRadius tileAll = BorderRadius.all(Radius.circular(tile));
  static const BorderRadius iconTileAll =
      BorderRadius.all(Radius.circular(iconTile));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Stroke weights. Borders are 2px everywhere — that is the signature of this
/// direction, in place of shadows.
class NfStroke {
  NfStroke._();

  static const double border = 2;

  /// Icon stroke weights. Icons are drawn, not emoji.
  static const double iconLight = 1.7;
  static const double icon = 2;
  static const double iconHeavy = 2.2;
}

/// Fixed sizes that more than one widget depends on.
class NfSize {
  NfSize._();

  static const double buttonPrimary = 52;
  static const double buttonSecondary = 46;

  /// How far a pushable control travels, and how tall its solid shadow is.
  static const double pressDepth = 4;

  /// Accessibility floor for anything tappable.
  static const double minTap = 44;

  /// Progress bar heights: prominent (goal, XP) and quiet (inline, list rows).
  static const double progressProminent = 10;
  static const double progressQuiet = 4;

  /// One SRS strength dot.
  static const double strengthDot = 9;
}
