import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/language_provider.dart';
import '../../providers/learning_language_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/learning_language_service.dart';
import '../nf_frontend_preference.dart';
import '../theme/nf_tokens.dart';
import '../widgets/nf_card.dart';
import '../widgets/nf_chip.dart';

/// App settings in the new frontend's paint.
///
/// The spec is `lib/screens/settings_page.dart` minus the parts that no longer
/// exist in this phase: there is no multi-theme picker (only the light/dark
/// brightness choice below), no classic-design toggle and no "new design
/// preview" card — this frontend *is* the frontend now.
///
/// What stays, with the same providers and services behind it:
/// - App language (EN/TR/DE) via [LanguageProvider], keys and snackbar copy
///   included.
/// - The learning profile (native language, English level, goal) via
///   [LearningLanguageProvider], analytics events included.
/// - Notifications and subscription as callbacks, so the shell decides the
///   routes; this page never imports it.
/// - Appearance: a light/dark row persisted on [NfFrontendPreference], which
///   is exactly where `NfThemeScope` and `NfShell` read the palette from.
///
/// The legacy settings screen had no sign-out, so this one does not either.
class NfSettingsPage extends StatelessWidget {
  const NfSettingsPage({
    super.key,
    this.onOpenNotifications,
    this.onManageSubscription,
  });

  final VoidCallback? onOpenNotifications;
  final VoidCallback? onManageSubscription;

  // ---------------------------------------------------------------------------
  // Labels
  // ---------------------------------------------------------------------------

  String _languageLabel(BuildContext context, String code) {
    switch (code) {
      case 'tr':
        return context.tr('language.turkish');
      case 'de':
        return context.tr('language.german');
      default:
        return context.tr('language.english');
    }
  }

  String _learningLanguageLabel(BuildContext context, String language) {
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

  String _learningGoalLabel(BuildContext context, String goal) {
    switch (goal) {
      case 'Vocabulary':
        return context.tr('learning.goal.vocabulary');
      case 'Exam':
        return context.tr('learning.goal.exam');
      case 'Work':
        return context.tr('learning.goal.work');
      case 'Travel':
        return context.tr('learning.goal.travel');
      default:
        return context.tr('learning.goal.speaking');
    }
  }

  // ---------------------------------------------------------------------------
  // Sheets
  // ---------------------------------------------------------------------------

  /// One picker sheet shape for every choice on this screen.
  Future<void> _showPickerSheet(
    BuildContext context, {
    required String title,
    required List<String> values,
    required String current,
    required String Function(String value) label,
    required Future<void> Function(String value) onSelect,
  }) async {
    final NfTokens t = NfTokens.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(NfRadius.card)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NfSpace.s20,
              NfSpace.s16,
              NfSpace.s20,
              NfSpace.s12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: NfTokens.display(size: NfFont.s18, color: t.ink),
                ),
                const SizedBox(height: NfSpace.s10),
                ...values.map((String value) {
                  final bool selected = value == current;
                  return _SheetOptionRow(
                    tokens: t,
                    label: label(value),
                    selected: selected,
                    onTap: () async {
                      final NavigatorState navigator =
                          Navigator.of(sheetContext);
                      await onSelect(value);
                      if (navigator.mounted) {
                        navigator.pop();
                      }
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessage(BuildContext context, String text) {
    final NfTokens t = NfTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
        ),
        backgroundColor: t.ink,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickAppLanguage(BuildContext context) async {
    final LanguageProvider provider = context.read<LanguageProvider>();
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NfTokens t = NfTokens.of(context);

    await _showPickerSheet(
      context,
      title: context.tr('settings.language.sheetTitle'),
      values: AppLocalizations.supportedLocales
          .map((Locale locale) => locale.languageCode)
          .toList(growable: false),
      current: provider.locale.languageCode,
      label: (String code) => _languageLabel(context, code),
      onSelect: (String code) async {
        await provider.selectLanguage(Locale(code));
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.t('language.changed'),
              style: NfTokens.body(size: NfFont.s135, color: t.primaryInk),
            ),
            backgroundColor: t.ink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  Future<void> _pickSourceLanguage(BuildContext context) async {
    final LearningLanguageProvider provider =
        context.read<LearningLanguageProvider>();
    final String changed = context.tr('settings.learning.sourceChanged');

    await _showPickerSheet(
      context,
      title: context.tr('settings.learning.sourceSheetTitle'),
      values: LearningLanguageService.supportedSourceLanguages,
      current: provider.sourceLanguage,
      label: (String value) => _learningLanguageLabel(context, value),
      onSelect: (String value) async {
        await provider.selectSourceLanguage(value);
        if (context.mounted) {
          _showMessage(context, changed);
        }
        await AnalyticsService.logLearningProfileUpdated(
          sourceLanguage: provider.sourceLanguage,
          englishLevel: provider.englishLevel,
          learningGoal: provider.learningGoal,
          source: 'settings_source_language',
        );
      },
    );
  }

  Future<void> _pickEnglishLevel(BuildContext context) async {
    final LearningLanguageProvider provider =
        context.read<LearningLanguageProvider>();
    final String changed = context.tr('settings.learning.sourceChanged');

    await _showPickerSheet(
      context,
      title: context.tr('settings.learning.levelSheetTitle'),
      values: LearningLanguageService.supportedEnglishLevels,
      current: provider.englishLevel,
      label: (String value) => value,
      onSelect: (String value) async {
        await provider.selectEnglishLevel(value);
        if (context.mounted) {
          _showMessage(context, changed);
        }
        await AnalyticsService.logLearningProfileUpdated(
          sourceLanguage: provider.sourceLanguage,
          englishLevel: provider.englishLevel,
          learningGoal: provider.learningGoal,
          source: 'settings_level',
        );
      },
    );
  }

  Future<void> _pickLearningGoal(BuildContext context) async {
    final LearningLanguageProvider provider =
        context.read<LearningLanguageProvider>();
    final String changed = context.tr('settings.learning.sourceChanged');

    await _showPickerSheet(
      context,
      title: context.tr('settings.learning.goalSheetTitle'),
      values: LearningLanguageService.supportedLearningGoals,
      current: provider.learningGoal,
      label: (String value) => _learningGoalLabel(context, value),
      onSelect: (String value) async {
        await provider.selectLearningGoal(value);
        if (context.mounted) {
          _showMessage(context, changed);
        }
        await AnalyticsService.logLearningProfileUpdated(
          sourceLanguage: provider.sourceLanguage,
          englishLevel: provider.englishLevel,
          learningGoal: provider.learningGoal,
          source: 'settings_goal',
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// The palette comes from the `NfThemeScope` the shell wraps this route in.
  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    final String languageCode =
        context.watch<LanguageProvider>().locale.languageCode;
    final LearningLanguageProvider learningProfile =
        context.watch<LearningLanguageProvider>();

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NfSpace.s12,
                NfSpace.s8,
                NfSpace.s16,
                NfSpace.s4,
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    iconSize: NfFont.s22,
                    color: t.ink,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                  const SizedBox(width: NfSpace.s4),
                  Expanded(
                    child: Text(
                      context.tr('settings.title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NfTokens.display(size: NfFont.s20, color: t.ink),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  NfSpace.s16,
                  NfSpace.s8,
                  NfSpace.s16,
                  NfSpace.s26,
                ),
                children: <Widget>[
                  Text(
                    context.tr('settings.subtitle'),
                    style:
                        NfTokens.body(size: NfFont.s135, color: t.inkMuted),
                  ),
                  const SizedBox(height: NfSpace.s14),
                  _buildPreferencesCard(context, t, languageCode),
                  const SizedBox(height: NfSpace.s14),
                  _buildLearningCard(context, t, learningProfile),
                  const SizedBox(height: NfSpace.s14),
                  _buildAboutCard(context, t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Language, appearance, notifications and subscription in one list card —
  /// the same row grammar the profile screen's settings card uses.
  Widget _buildPreferencesCard(
    BuildContext context,
    NfTokens t,
    String languageCode,
  ) {
    return NfCard(
      padding: EdgeInsets.zero,
      clipContent: true,
      child: Column(
        children: <Widget>[
          _SettingsRow(
            icon: Icons.language_rounded,
            label: context.tr('settings.language.title'),
            tokens: t,
            trailing: NfChip(
              label: _languageLabel(context, languageCode),
              variant: NfChipVariant.selected,
              dense: true,
            ),
            onTap: () => unawaited(_pickAppLanguage(context)),
          ),
          _RowDivider(tokens: t),
          _buildAppearanceRow(context, t),
          _RowDivider(tokens: t),
          _SettingsRow(
            icon: Icons.notifications_none_rounded,
            label: context.tr('profile.notificationPrefs'),
            tokens: t,
            onTap: onOpenNotifications,
          ),
          _RowDivider(tokens: t),
          _SettingsRow(
            icon: Icons.workspace_premium_outlined,
            // TODO(i18n): needs a key
            label: 'Manage subscription',
            tokens: t,
            onTap: onManageSubscription,
          ),
        ],
      ),
    );
  }

  /// The light/dark choice. There is one persisted value and it lives on
  /// [NfFrontendPreference] — the same object `NfThemeScope` and the shell
  /// resolve the palette from, so the choice takes effect on this very screen
  /// the moment a chip is tapped.
  Widget _buildAppearanceRow(BuildContext context, NfTokens t) {
    final NfFrontendPreference? preference =
        Provider.of<NfFrontendPreference?>(context);
    final bool isDark = t.isDark;

    return _SettingsRow(
      icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
      // TODO(i18n): needs a key
      label: 'Appearance',
      tokens: t,
      showChevron: false,
      // No onTap of its own: the chips are the control. A row that also
      // toggled would make the tap target ambiguous.
      onTap: null,
      enabledLook: preference != null,
      trailing: preference == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                NfChip(
                  // TODO(i18n): needs a key
                  label: 'Light',
                  icon: Icons.light_mode_outlined,
                  dense: true,
                  variant: isDark
                      ? NfChipVariant.unselected
                      : NfChipVariant.selected,
                  onTap: () => unawaited(preference.setDarkOverride(false)),
                ),
                const SizedBox(width: NfSpace.s6),
                NfChip(
                  // TODO(i18n): needs a key
                  label: 'Dark',
                  icon: Icons.dark_mode_outlined,
                  dense: true,
                  variant: isDark
                      ? NfChipVariant.selected
                      : NfChipVariant.unselected,
                  onTap: () => unawaited(preference.setDarkOverride(true)),
                ),
              ],
            ),
    );
  }

  Widget _buildLearningCard(
    BuildContext context,
    NfTokens t,
    LearningLanguageProvider learningProfile,
  ) {
    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.tr('settings.learning.title'),
            style: NfTokens.display(size: NfFont.s16, color: t.ink),
          ),
          const SizedBox(height: NfSpace.s6),
          Text(
            context.tr('settings.learning.subtitle'),
            style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
          ),
          const SizedBox(height: NfSpace.s12),
          Text(
            '${context.tr('settings.learning.target')}: '
            '${_learningLanguageLabel(context, learningProfile.targetLanguage)}',
            style: NfTokens.body(
              size: NfFont.s13,
              weight: NfTokens.bodyEmphasisWeight,
              color: t.inkMuted,
            ),
          ),
          const SizedBox(height: NfSpace.s12),
          Wrap(
            spacing: NfSpace.s8,
            runSpacing: NfSpace.s8,
            children: <Widget>[
              NfChip(
                icon: Icons.translate_rounded,
                label: '${context.tr('settings.learning.source')}: '
                    '${_learningLanguageLabel(context, learningProfile.sourceLanguage)}',
                onTap: () => unawaited(_pickSourceLanguage(context)),
              ),
              NfChip(
                icon: Icons.school_outlined,
                label: '${context.tr('settings.learning.level')}: '
                    '${learningProfile.englishLevel}',
                onTap: () => unawaited(_pickEnglishLevel(context)),
              ),
              NfChip(
                icon: Icons.flag_outlined,
                label: '${context.tr('settings.learning.goal')}: '
                    '${_learningGoalLabel(context, learningProfile.learningGoal)}',
                onTap: () => unawaited(_pickLearningGoal(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context, NfTokens t) {
    return NfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.tr('settings.about.title'),
            style: NfTokens.display(size: NfFont.s16, color: t.ink),
          ),
          const SizedBox(height: NfSpace.s6),
          Text(
            context.tr('settings.about.subtitle'),
            style: NfTokens.body(size: NfFont.s125, color: t.inkMuted),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PIECES
// ═══════════════════════════════════════════════════════════════════════════

class _RowDivider extends StatelessWidget {
  const _RowDivider({required this.tokens});

  final NfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: NfStroke.border,
      child: ColoredBox(color: tokens.border),
    );
  }
}

/// One row of a settings list card. Same grammar as the profile screen's rows:
/// icon tile, label, optional trailing value, chevron for rows that navigate.
class _SettingsRow extends StatefulWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.tokens,
    required this.onTap,
    this.trailing,
    this.showChevron = true,
    this.enabledLook,
  });

  final IconData icon;
  final String label;
  final NfTokens tokens;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;

  /// Rows whose control lives in [trailing] have no [onTap] but must not look
  /// disabled. Null falls back to "enabled iff tappable".
  final bool? enabledLook;

  @override
  State<_SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<_SettingsRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = widget.tokens;
    final bool enabled = widget.enabledLook ?? widget.onTap != null;

    final Widget row = Container(
      color: _pressed ? t.raised : t.surface,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(
        horizontal: NfSpace.s16,
        vertical: NfSpace.s12,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: NfRadius.iconTileAll,
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: enabled ? t.primaryText : t.inkFaint,
            ),
          ),
          const SizedBox(width: NfSpace.s14),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NfTokens.body(
                size: NfFont.s15,
                weight: NfTokens.bodyEmphasisWeight,
                color: enabled ? t.ink : t.inkFaint,
              ),
            ),
          ),
          if (widget.trailing != null) ...<Widget>[
            const SizedBox(width: NfSpace.s10),
            widget.trailing!,
          ],
          if (widget.showChevron) ...<Widget>[
            const SizedBox(width: NfSpace.s8),
            Icon(Icons.chevron_right_rounded, size: 20, color: t.inkFaint),
          ],
        ],
      ),
    );

    if (widget.onTap == null) return row;

    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onTap,
          child: row,
        ),
      ),
    );
  }
}

/// One option in a picker sheet: radio-style state, full-width tap target.
class _SheetOptionRow extends StatelessWidget {
  const _SheetOptionRow({
    required this.tokens,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final NfTokens tokens;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: NfSize.minTap),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? tokens.primaryText : tokens.inkFaint,
                ),
                const SizedBox(width: NfSpace.s12),
                Expanded(
                  child: Text(
                    label,
                    style: NfTokens.body(
                      size: NfFont.s15,
                      weight: selected
                          ? NfTokens.bodyEmphasisWeight
                          : NfTokens.bodyWeight,
                      color: tokens.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
