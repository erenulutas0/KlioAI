import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/support_ticket_service.dart';

/// One-tap "this is wrong" for a piece of generated content.
///
/// This exists because of a specific failure. For three months the app served hardcoded
/// template sentences — "Maya noticed evaluate during the trip" — to learners as if a model
/// had written them, and every one of those requests was recorded as a success. The
/// instrumentation could see that a call returned HTTP 200. It could not see that the
/// sentence was nonsense, and no amount of additional metrics would have.
///
/// Only a person can report that, and only if reporting costs them almost nothing. A
/// support form asking a learner to describe the problem, name the screen and remember the
/// sentence will be used by nobody. So the button carries the content and the context
/// itself: the learner presses once and optionally adds a word.
class ReportContentButton extends StatelessWidget {
  const ReportContentButton({
    super.key,
    required this.content,
    required this.surface,
    this.contentKind = 'sentence',
    this.extra,
    this.compact = true,
  });

  /// The exact text the learner is looking at. Sent verbatim — a paraphrase would lose the
  /// thing that makes the report actionable.
  final String content;

  /// Where in the app this was shown, e.g. 'translation_practice', 'daily_words'.
  final String surface;

  /// What kind of content it is, so reports can be grouped by generator.
  final String contentKind;

  /// Anything else worth knowing: the target word, the level, the grammar topic.
  final Map<String, dynamic>? extra;

  final bool compact;

  static bool _isTurkish(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'tr';

  Future<void> _report(BuildContext context) async {
    // Everything taken from the context is read up front, before the first await. After the
    // dialog closes this widget may be gone, and reaching back into a dead context is the
    // classic way a "thanks, we got it" toast turns into a crash.
    final isTurkish = _isTurkish(context);
    final localeCode = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isTurkish ? 'Bu içerik hatalı mı?' : 'Is this content wrong?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTurkish
                  ? 'İçerik bize otomatik olarak iletilecek. İstersen kısaca neyin yanlış olduğunu yazabilirsin.'
                  : 'The content is sent automatically. You can add a word about what is wrong if you like.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: isTurkish
                    ? 'Örn: cümle anlamsız, çeviri yanlış'
                    : 'e.g. the sentence makes no sense',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(isTurkish ? 'Vazgeç' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isTurkish ? 'Bildir' : 'Report'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Collected here rather than asked of the learner: they should not have to know the
    // build number to be useful.
    String version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // A missing version must not stop the report.
    }

    final note = noteController.text.trim();
    try {
      await SupportTicketService().createTicket(
        type: 'CONTENT_REPORT',
        title: 'Content report: $contentKind on $surface',
        message: note.isEmpty ? '(no note)' : note,
        locale: localeCode,
        context: {
          'surface': surface,
          'contentKind': contentKind,
          'content': content,
          'appVersion': version,
          if (extra != null) ...extra!,
        },
      );
      messenger.showSnackBar(SnackBar(
        content: Text(isTurkish
            ? 'Teşekkürler, bildirimin bize ulaştı.'
            : 'Thank you — your report reached us.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(isTurkish
            ? 'Bildirim gönderilemedi, daha sonra tekrar dene.'
            : 'The report could not be sent, please try again later.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTurkish = _isTurkish(context);
    if (compact) {
      return IconButton(
        key: const ValueKey('report-content-button'),
        onPressed: () => _report(context),
        icon: Icon(
          Icons.flag_outlined,
          size: 18,
          color: Colors.white.withValues(alpha: 0.45),
        ),
        tooltip: isTurkish ? 'Hatalı içerik bildir' : 'Report wrong content',
        // Deliberately understated. This should be findable when something is wrong and
        // invisible when nothing is.
        visualDensity: VisualDensity.compact,
      );
    }
    return TextButton.icon(
      key: const ValueKey('report-content-button'),
      onPressed: () => _report(context),
      icon: const Icon(Icons.flag_outlined, size: 16),
      label: Text(
        isTurkish ? 'Hatalı içerik bildir' : 'Report wrong content',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
