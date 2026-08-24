import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/language_provider.dart';
import '../../providers/learning_language_provider.dart';
import 'nf_landing_page.dart';
import '../../services/analytics_service.dart';
import '../../services/app_tour_service.dart';
import '../../services/learning_language_service.dart';
import '../theme/nf_theme_scope.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_button.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// The brand mark, white on transparent. Same file the native Android splash
/// draws, so the violet tile below repeats the launch screen rather than
/// introducing a second logo.
const String _kMarkAsset = 'assets/images/flat_k_white.png';

/// How long a page change takes. Matches the old flow so the swipe and the
/// button feel the same.
const Duration _kPageDuration = Duration(milliseconds: 500);

/// The fade the login page arrives on, kept from `OnboardingScreen`.
const Duration _kHandoffDuration = Duration(milliseconds: 800);

/// Everything a learner does before signing in, in the new design.
///
/// This is `lib/screens/language_selection_page.dart` and
/// `lib/screens/onboarding_screen.dart` folded into a single flow:
///
///  1. the app language (only on a first run — see [showLanguageStep]),
///  2. a three-page tour,
///  3. the learning profile.
///
/// Nothing about the behaviour moved. The language is persisted through
/// [LanguageProvider.selectLanguage], the profile through
/// [LearningLanguageProvider], the tour is marked done with
/// [AppTourService.markCompleted], and the same analytics events fire at the
/// same moments. The old five slides became three: the two that went are
/// feature boasts ("Glow Effects", "Animated Stats") that describe the app's
/// paint rather than what a learner will do with it.
///
/// The page runs before `NfShell` exists, so it installs [NfThemeScope] itself
/// instead of relying on a caller to do it, and it reads nothing from
/// `AppStateProvider` — there is no user yet.
class NfOnboardingPage extends StatelessWidget {
  const NfOnboardingPage({
    super.key,
    this.fromSettings = false,
    this.initialPage = 0,
    this.showLanguageStep,
    this.nextPageBuilder,
  });

  /// Replaying the tour from settings. Changes the analytics source and makes
  /// the last button pop instead of replacing the route, exactly as the old
  /// screen did.
  final bool fromSettings;

  /// Index into the pager (tour slides first, [profilePageIndex] last).
  /// `OnboardingScreen.initialPage` under a different name.
  final int initialPage;

  /// Forces the app-language step on or off.
  ///
  /// Null means decide: show it on a first run that has not already picked a
  /// language, which is precisely the condition `AppEntryGate` used to branch
  /// on before it pushed `LanguageSelectionPage`.
  final bool? showLanguageStep;

  /// Where finishing goes on a first run. Null keeps the old destination, so
  /// the flow always ends somewhere even before anything wires it up; the
  /// shell should pass the new sign-in page here.
  final WidgetBuilder? nextPageBuilder;

  /// How many pages the pager holds: the tour, then the profile.
  static const int pageCount = _kTourSlideCount + 1;

  /// The learning-profile step. Skip and "replay from settings" both aim here,
  /// and it is what `OnboardingScreen(initialPage: 4)` used to mean.
  static const int profilePageIndex = pageCount - 1;

  @override
  Widget build(BuildContext context) {
    return NfThemeScope(
      child: _NfOnboardingFlow(
        fromSettings: fromSettings,
        initialPage: initialPage,
        showLanguageStep: showLanguageStep,
        nextPageBuilder: nextPageBuilder,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW
// ═══════════════════════════════════════════════════════════════════════════

class _NfOnboardingFlow extends StatefulWidget {
  const _NfOnboardingFlow({
    required this.fromSettings,
    required this.initialPage,
    required this.showLanguageStep,
    required this.nextPageBuilder,
  });

  final bool fromSettings;
  final int initialPage;
  final bool? showLanguageStep;
  final WidgetBuilder? nextPageBuilder;

  @override
  State<_NfOnboardingFlow> createState() => _NfOnboardingFlowState();
}

class _NfOnboardingFlowState extends State<_NfOnboardingFlow> {
  late final PageController _pageController;
  late int _page;

  /// Resolved once, in [didChangeDependencies]. Latched because selecting a
  /// language flips `hasExplicitSelection`, and a step must not vanish from
  /// under the learner mid-flow.
  bool _resolvedLanguageStep = false;
  bool _showLanguageStep = false;

  Locale? _selectedLocale;
  bool _savingLanguage = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(0, NfOnboardingPage.pageCount - 1);
    _pageController = PageController(initialPage: _page);
    AnalyticsService.logOnboardingStarted(
      source: widget.fromSettings ? 'settings' : 'first_run',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedLanguageStep) {
      return;
    }
    _resolvedLanguageStep = true;

    final LanguageProvider language = context.read<LanguageProvider>();
    // The old screen always started on the detected language. It only ever ran
    // when nothing had been chosen yet, so honouring an existing choice here
    // cannot change the first-run path — it only makes a forced replay sane.
    _selectedLocale = language.hasExplicitSelection
        ? language.locale
        : language.detectedLocale;
    _showLanguageStep = widget.showLanguageStep ??
        (!widget.fromSettings &&
            widget.initialPage == 0 &&
            !language.hasExplicitSelection);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Steps
  // ---------------------------------------------------------------------------

  Future<void> _continueFromLanguage() async {
    final Locale? locale = _selectedLocale;
    if (locale == null || _savingLanguage) {
      return;
    }
    setState(() => _savingLanguage = true);
    await context.read<LanguageProvider>().selectLanguage(locale);
    if (!mounted) {
      return;
    }
    // The old screen handed off to the splash, which then decided between the
    // tour and the landing page. The tour is right here now, so the step just
    // steps aside. Everything below this line is already rebuilding in the
    // language that was just chosen.
    setState(() {
      _savingLanguage = false;
      _showLanguageStep = false;
    });
  }

  void _onPageChanged(int index) {
    if (_page == index) {
      return;
    }
    setState(() => _page = index);
  }

  void _back() {
    _pageController.previousPage(
      duration: _kPageDuration,
      curve: Curves.easeInOut,
    );
  }

  void _next() {
    if (_page >= NfOnboardingPage.profilePageIndex) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: _kPageDuration,
      curve: Curves.easeInOut,
    );
  }

  void _skip() {
    _pageController.animateToPage(
      NfOnboardingPage.profilePageIndex,
      duration: _kPageDuration,
      curve: Curves.easeInOut,
    );
  }

  /// The same three writes the old screen made, in the same order: report the
  /// profile, mark the tour done, then leave.
  Future<void> _finish() async {
    if (_finishing) {
      return;
    }
    setState(() => _finishing = true);

    final LearningLanguageProvider profile =
        context.read<LearningLanguageProvider>();
    final NavigatorState navigator = Navigator.of(context);
    final bool fromSettings = widget.fromSettings;
    final WidgetBuilder? nextPage = widget.nextPageBuilder;

    await AnalyticsService.logLearningProfileUpdated(
      sourceLanguage: profile.sourceLanguage,
      englishLevel: profile.englishLevel,
      learningGoal: profile.learningGoal,
      source: fromSettings ? 'settings_onboarding' : 'onboarding',
    );
    await AppTourService().markCompleted(
      source: fromSettings ? 'settings' : 'first_run',
    );
    if (!mounted) {
      return;
    }

    if (fromSettings) {
      navigator.pop();
      return;
    }

    navigator.pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) =>
            nextPage?.call(context) ?? const NfLandingPage(),
        transitionsBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: _kHandoffDuration,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: _showLanguageStep ? _buildLanguageStep() : _buildPager(),
      ),
    );
  }

  Widget _buildLanguageStep() {
    final LanguageProvider language = context.watch<LanguageProvider>();

    return _LanguageStep(
      detected: language.detectedLocale,
      selected: _selectedLocale ?? language.detectedLocale,
      saving: _savingLanguage,
      onSelect: (Locale locale) => setState(() => _selectedLocale = locale),
      onContinue: _continueFromLanguage,
    );
  }

  Widget _buildPager() {
    final bool onLastPage = _page >= NfOnboardingPage.profilePageIndex;

    return Column(
      children: <Widget>[
        _FlowHeader(
          onBack: _page > 0 ? _back : null,
          onSkip: onLastPage ? null : _skip,
        ),
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: const <Widget>[
              _TourSlide(
                icon: LucideIcons.bookMarked,
                titleKey: 'onboarding.tour.deck.title',
                bodyKey: 'onboarding.tour.deck.body',
                pointKeys: <String>[
                  'onboarding.tour.deck.p1',
                  'onboarding.tour.deck.p2',
                  'onboarding.tour.deck.p3',
                ],
              ),
              _TourSlide(
                icon: LucideIcons.repeat,
                titleKey: 'onboarding.tour.review.title',
                bodyKey: 'onboarding.tour.review.body',
                pointKeys: <String>[
                  'onboarding.tour.review.p1',
                  'onboarding.tour.review.p2',
                  'onboarding.tour.review.p3',
                ],
              ),
              _TourSlide(
                icon: LucideIcons.messagesSquare,
                titleKey: 'onboarding.tour.practice.title',
                bodyKey: 'onboarding.tour.practice.body',
                pointKeys: <String>[
                  'onboarding.tour.practice.p1',
                  'onboarding.tour.practice.p2',
                  'onboarding.tour.practice.p3',
                ],
              ),
              _ProfileStep(),
            ],
          ),
        ),
        _FlowFooter(
          page: _page,
          finishing: _finishing,
          onNext: _next,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// APP LANGUAGE
// ═══════════════════════════════════════════════════════════════════════════

/// Step one: which language the app itself speaks.
///
/// The list shows each language written in itself — a learner looking for
/// Turkish scans for "Türkçe", not for whatever the current interface language
/// happens to call it.
class _LanguageStep extends StatelessWidget {
  const _LanguageStep({
    required this.detected,
    required this.selected,
    required this.saving,
    required this.onSelect,
    required this.onContinue,
  });

  static const double _markTile = 72;
  static const double _markImage = 40;

  final Locale detected;
  final Locale selected;
  final bool saving;
  final ValueChanged<Locale> onSelect;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              NfSpace.s16,
              NfSpace.s20,
              NfSpace.s16,
              NfSpace.s16,
            ),
            children: <Widget>[
              Container(
                width: _markTile,
                height: _markTile,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primary,
                  borderRadius: NfRadius.cardAll,
                ),
                child: const Image(
                  image: AssetImage(_kMarkAsset),
                  width: _markImage,
                  height: _markImage,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: NfSpace.s22),
              Text(
                context.tr('onboarding.lang.title'),
                style: NfTokens.display(size: NfFont.s25, color: t.ink),
              ),
              const SizedBox(height: NfSpace.s10),
              Text(
                context.tr('onboarding.lang.subtitle'),
                style: NfTokens.body(size: NfFont.s145, color: t.inkMuted),
              ),
              const SizedBox(height: NfSpace.s20),
              for (final Locale locale in AppLocalizations.supportedLocales)
                Padding(
                  padding: const EdgeInsets.only(bottom: NfSpace.s10),
                  child: _LanguageRow(
                    key: ValueKey<String>(
                      'onboarding-language-${locale.languageCode}',
                    ),
                    label: _appLanguageName(context, locale.languageCode),
                    code: locale.languageCode.toUpperCase(),
                    selected: selected.languageCode == locale.languageCode,
                    suggested: detected.languageCode == locale.languageCode,
                    onTap: () => onSelect(locale),
                  ),
                ),
              const SizedBox(height: NfSpace.s6),
              Text(
                context
                    .tr('onboarding.lang.deviceHint')
                    .replaceAll(
                      '{lang}',
                      _appLanguageName(context, detected.languageCode),
                    ),
                style: NfTokens.body(size: NfFont.s125, color: t.inkFaint),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NfSpace.s16,
            NfSpace.s8,
            NfSpace.s16,
            NfSpace.s16,
          ),
          child: NfPrimaryButton(
            key: const ValueKey<String>('onboarding-language-continue'),
            label: context.tr('onboarding.next'),
            busy: saving,
            onPressed: onContinue,
          ),
        ),
      ],
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    super.key,
    required this.label,
    required this.code,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });

  static const double _tileSize = 44;
  static const double _markSize = 26;

  final String label;

  /// The ISO code, drawn in the tile. Two neutral letters read the same in
  /// every interface language, which is what this row needs.
  final String code;

  final bool selected;

  /// The device's own language. Marked, never forced.
  final bool suggested;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return NfCard(
      onTap: onTap,
      padding: const EdgeInsets.all(NfSpace.s12),
      borderRadius: NfRadius.tileAll,
      backgroundColor: selected ? t.primarySoft : t.surface,
      borderColor: selected ? t.primary : t.border,
      child: Row(
        children: <Widget>[
          Container(
            width: _tileSize,
            height: _tileSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? t.surface : t.raised,
              borderRadius: NfRadius.iconTileAll,
              border: Border.fromBorderSide(
                t.sideOf(selected ? t.primary : t.border),
              ),
            ),
            child: Text(
              code,
              style: NfTokens.display(
                size: NfFont.s15,
                color: selected ? t.primaryText : t.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: NfSpace.s12),
          Expanded(
            child: Text(
              label,
              style: NfTokens.body(
                size: NfFont.s16,
                weight: NfTokens.bodyEmphasisWeight,
                color: t.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (suggested) ...<Widget>[
            const SizedBox(width: NfSpace.s8),
            NfChip(
              label: context.tr('onboarding.lang.suggested'),
              dense: true,
            ),
          ],
          const SizedBox(width: NfSpace.s10),
          Container(
            width: _markSize,
            height: _markSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? t.primary : NfTokens.transparent,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                t.sideOf(selected ? t.primary : t.border),
              ),
            ),
            child: selected
                ? Icon(LucideIcons.check, size: 15, color: t.primaryInk)
                : null,
          ),
        ],
      ),
    );
  }
}

/// Each supported interface language, written in itself.
String _appLanguageName(BuildContext context, String code) {
  switch (code) {
    case 'tr':
      return context.tr('onboarding.lang.name.tr');
    case 'de':
      return context.tr('onboarding.lang.name.de');
    default:
      return context.tr('onboarding.lang.name.en');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHROME
// ═══════════════════════════════════════════════════════════════════════════

class _FlowHeader extends StatelessWidget {
  const _FlowHeader({required this.onBack, required this.onSkip});

  /// Null on the first slide: there is nothing behind it.
  final VoidCallback? onBack;

  /// Null on the profile step, which is not skippable.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final VoidCallback? back = onBack;
    final VoidCallback? skip = onSkip;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s10,
        NfSpace.s8,
        NfSpace.s10,
        NfSpace.s4,
      ),
      child: Row(
        children: <Widget>[
          // Both slots keep their size when empty, so the header does not jump
          // between pages.
          if (back == null)
            const SizedBox(width: NfSize.minTap, height: NfSize.minTap)
          else
            IconButton(
              onPressed: back,
              icon: const Icon(LucideIcons.arrowLeft),
              iconSize: NfFont.s22,
              color: t.ink,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: NfSize.minTap,
                height: NfSize.minTap,
              ),
              tooltip: context.tr('common.back'),
            ),
          const Spacer(),
          if (skip == null)
            const SizedBox(width: NfSize.minTap, height: NfSize.minTap)
          else
            TextButton(
              key: const ValueKey<String>('onboarding-skip-button'),
              onPressed: skip,
              style: TextButton.styleFrom(
                foregroundColor: t.inkMuted,
                minimumSize: const Size(NfSize.minTap, NfSize.minTap),
                padding: const EdgeInsets.symmetric(horizontal: NfSpace.s12),
              ),
              child: Text(
                context.tr('common.skip'),
                style: NfTokens.body(
                  size: NfFont.s14,
                  weight: NfTokens.bodyEmphasisWeight,
                  color: t.inkMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FlowFooter extends StatelessWidget {
  const _FlowFooter({
    required this.page,
    required this.finishing,
    required this.onNext,
  });

  final int page;
  final bool finishing;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final bool onLastPage = page >= NfOnboardingPage.profilePageIndex;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s12,
        NfSpace.s16,
        NfSpace.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Dots(count: NfOnboardingPage.pageCount, index: page),
          const SizedBox(height: NfSpace.s16),
          NfPrimaryButton(
            key: ValueKey<String>(
              onLastPage ? 'onboarding-start-button' : 'onboarding-next-button',
            ),
            label: onLastPage
                ? context.tr('onboarding.finish')
                : context.tr('onboarding.next'),
            icon: onLastPage ? LucideIcons.arrowRight : null,
            busy: finishing,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// Where the learner is in the flow. The active dot stretches instead of
/// glowing — the direction has nothing to glow with.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  static const double _size = 8;
  static const double _activeWidth = 26;

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Semantics(
      label: context
          .tr('onboarding.progress')
          .replaceAll('{a}', '${index + 1}')
          .replaceAll('{b}', '$count'),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < count; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: NfSpace.s6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: i == index ? _activeWidth : _size,
              height: _size,
              decoration: BoxDecoration(
                color: i == index ? t.primary : t.border,
                borderRadius: NfRadius.pillAll,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TOUR
// ═══════════════════════════════════════════════════════════════════════════

/// How many slides the tour has.
const int _kTourSlideCount = 3;

/// One tour slide: a mark, a claim, and three lines that back it up.
///
/// The slide takes localization keys rather than strings so it can stay
/// `const` at the call site; `context.tr` then runs inside [build], where there
/// is a context to run it with.
class _TourSlide extends StatelessWidget {
  const _TourSlide({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    required this.pointKeys,
  });

  static const double _iconTile = 76;

  final IconData icon;
  final String titleKey;
  final String bodyKey;
  final List<String> pointKeys;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s16,
        NfSpace.s16,
        NfSpace.s16,
      ),
      children: <Widget>[
        Center(
          child: Container(
            width: _iconTile,
            height: _iconTile,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: NfRadius.cardAll,
              border: Border.fromBorderSide(t.sideOf(t.primary)),
            ),
            child: Icon(icon, size: 34, color: t.primaryText),
          ),
        ),
        const SizedBox(height: NfSpace.s22),
        Text(
          context.tr(titleKey),
          textAlign: TextAlign.center,
          style: NfTokens.display(size: NfFont.s25, color: t.ink),
        ),
        const SizedBox(height: NfSpace.s12),
        Text(
          context.tr(bodyKey),
          textAlign: TextAlign.center,
          style: NfTokens.body(size: NfFont.s145, color: t.inkMuted),
        ),
        const SizedBox(height: NfSpace.s22),
        NfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < pointKeys.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: NfSpace.s14),
                _TourPoint(labelKey: pointKeys[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TourPoint extends StatelessWidget {
  const _TourPoint({required this.labelKey});

  static const double _markSize = 24;

  final String labelKey;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: _markSize,
          height: _markSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.primarySoft,
            shape: BoxShape.circle,
            border: Border.fromBorderSide(t.sideOf(t.primary)),
          ),
          child: Icon(LucideIcons.check, size: 14, color: t.primaryText),
        ),
        const SizedBox(width: NfSpace.s12),
        Expanded(
          child: Text(
            context.tr(labelKey),
            style: NfTokens.body(
              size: NfFont.s145,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.ink,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LEARNING PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/// The last step, and the only one that feeds behaviour rather than
/// expectations: the native language decides what meanings and corrections are
/// written in, the CEFR level decides how hard the generated material is, and
/// the goal is carried into the profile the tutor is briefed with.
///
/// Each chip writes straight through [LearningLanguageProvider], which persists
/// to `SharedPreferences` and pushes the value into
/// [LearningLanguageService] — the same path the old screen used, so a learner
/// who backs out mid-step keeps what they already tapped.
class _ProfileStep extends StatelessWidget {
  const _ProfileStep();

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final LearningLanguageProvider profile =
        context.watch<LearningLanguageProvider>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NfSpace.s16,
        NfSpace.s16,
        NfSpace.s16,
        NfSpace.s16,
      ),
      children: <Widget>[
        Text(
          context.tr('onboarding.setup.title'),
          style: NfTokens.display(size: NfFont.s23, color: t.ink),
        ),
        const SizedBox(height: NfSpace.s10),
        Text(
          context.tr('onboarding.setup.subtitle'),
          style: NfTokens.body(size: NfFont.s14, color: t.inkMuted),
        ),
        const SizedBox(height: NfSpace.s18),
        _ChoiceSection(
          title: context.tr('onboarding.setup.native'),
          hint: context.tr('onboarding.setup.nativeHint'),
          children: <Widget>[
            for (final String language
                in LearningLanguageService.supportedSourceLanguages)
              NfChip(
                key: ValueKey<String>('onboarding-source-$language'),
                label: _sourceLanguageLabel(context, language),
                variant: profile.sourceLanguage == language
                    ? NfChipVariant.selected
                    : NfChipVariant.unselected,
                onTap: () => profile.selectSourceLanguage(language),
              ),
          ],
        ),
        const SizedBox(height: NfSpace.s12),
        _ChoiceSection(
          title: context.tr('onboarding.setup.level'),
          hint: context.tr('onboarding.setup.levelHint'),
          children: <Widget>[
            for (final String level
                in LearningLanguageService.supportedEnglishLevels)
              NfChip(
                key: ValueKey<String>('onboarding-level-$level'),
                // A CEFR band is the same three characters in every language.
                label: level,
                variant: profile.englishLevel == level
                    ? NfChipVariant.selected
                    : NfChipVariant.unselected,
                onTap: () => profile.selectEnglishLevel(level),
              ),
          ],
        ),
        const SizedBox(height: NfSpace.s12),
        _ChoiceSection(
          title: context.tr('onboarding.setup.goal'),
          children: <Widget>[
            for (final String goal
                in LearningLanguageService.supportedLearningGoals)
              NfChip(
                key: ValueKey<String>('onboarding-goal-$goal'),
                label: _learningGoalLabel(context, goal),
                variant: profile.learningGoal == goal
                    ? NfChipVariant.selected
                    : NfChipVariant.unselected,
                onTap: () => profile.selectLearningGoal(goal),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceSection extends StatelessWidget {
  const _ChoiceSection({
    required this.title,
    required this.children,
    this.hint,
  });

  final String title;
  final String? hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final String? hintText = hint;

    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            style: NfTokens.display(size: NfFont.s16, color: t.ink),
          ),
          if (hintText != null) ...<Widget>[
            const SizedBox(height: NfSpace.s4),
            Text(
              hintText,
              style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
            ),
          ],
          const SizedBox(height: NfSpace.s10),
          Wrap(
            spacing: NfSpace.s8,
            runSpacing: NfSpace.s4,
            children: children,
          ),
        ],
      ),
    );
  }
}

/// The languages a learner can already speak. These are the app-wide
/// `language.*` keys, so the name reads the same here as in settings and on the
/// home tab's language sheet.
String _sourceLanguageLabel(BuildContext context, String language) {
  switch (language) {
    case 'Turkish':
      return context.tr('language.turkish');
    case 'Spanish':
      return context.tr('language.spanish');
    case 'Portuguese':
      return context.tr('language.portuguese');
    case 'Indonesian':
      return context.tr('language.indonesian');
    case 'German':
      return context.tr('language.german');
    case 'French':
      return context.tr('language.french');
    default:
      return context.tr('language.english');
  }
}

/// Short labels: these are pills on a phone, and the long form
/// ("Exam preparation") was clipping.
String _learningGoalLabel(BuildContext context, String goal) {
  switch (goal) {
    case 'Vocabulary':
      return context.tr('onboarding.goal.vocabulary');
    case 'Exam':
      return context.tr('onboarding.goal.exam');
    case 'Work':
      return context.tr('onboarding.goal.work');
    case 'Travel':
      return context.tr('onboarding.goal.travel');
    default:
      return context.tr('onboarding.goal.speaking');
  }
}
