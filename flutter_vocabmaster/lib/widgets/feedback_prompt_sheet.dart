import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/feedback_prompt_service.dart';
import '../services/in_app_review_service.dart';
import '../services/locale_text_service.dart';
import '../services/support_ticket_service.dart';

/// One question, asked once, after a session that went well.
///
/// The app can measure that somebody opened it, finished a review and earned XP. It cannot
/// measure whether the sentences made sense, whether the translations were right, or whether
/// any of it is teaching them anything — and it spent three months serving hardcoded
/// template sentences while every one of those requests was logged as a success. The only
/// instrument that catches that is a person, and only if being asked costs them one tap.
///
/// Three answers rather than five stars: a star rating produces a number that looks like
/// data and says nothing about what to fix. "Not really" opens a text box, and what they
/// write goes to the same inbox as the content reports.
class FeedbackPromptSheet extends StatefulWidget {
  const FeedbackPromptSheet._({required this.completions});

  final int completions;

  /// Shows the sheet if it is due. Returns without doing anything if it is not.
  ///
  /// Safe to call at the end of any session: the service owns the decision, so no caller
  /// has to know how often it has been asked, and no caller has to thread a counter
  /// through. Adding this to a new surface is one line.
  static Future<void> maybeShow(BuildContext context) async {
    final service = FeedbackPromptService();
    final completions = await service.completions();
    if (!await service.shouldAsk(completions)) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedbackPromptSheet._(completions: completions),
    );
  }

  @override
  State<FeedbackPromptSheet> createState() => _FeedbackPromptSheetState();
}

class _FeedbackPromptSheetState extends State<FeedbackPromptSheet> {
  final _noteController = TextEditingController();
  String? _answer;
  bool _sending = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _choose(String answer) async {
    final service = FeedbackPromptService();
    await service.recordAnswer(answer, widget.completions);

    if (answer == FeedbackPromptService.answerGood) {
      // Earned, not assumed. This is the only path to the store.
      final review = InAppReviewService();
      if (await review.isEligibleForStorePrompt()) {
        await review.requestStoreReview();
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    // Anything short of "yes" is the interesting answer, so ask what is wrong rather than
    // thanking them and closing.
    if (mounted) {
      setState(() => _answer = answer);
    }
  }

  Future<void> _sendNote() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final isTurkish = LocaleTextService.isTurkish;
    final note = _noteController.text.trim();

    setState(() => _sending = true);

    String version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // A missing version must not stop the report.
    }

    try {
      await SupportTicketService().createTicket(
        type: 'FEEDBACK',
        title: 'In-app feedback: ${_answer ?? 'unknown'}',
        message: note.isEmpty ? '(no note)' : note,
        locale: isTurkish ? 'tr' : 'en',
        context: {
          'answer': _answer,
          'completions': widget.completions,
          'appVersion': version,
        },
      );
      messenger.showSnackBar(SnackBar(
        content: Text(isTurkish
            ? 'Teşekkürler, bu bize gerçekten yardımcı oluyor.'
            : 'Thank you — this genuinely helps.'),
      ));
    } catch (_) {
      // The answer itself is already recorded locally, so a failed send costs us the note
      // and nothing else. Saying so is better than a silent failure.
      messenger.showSnackBar(SnackBar(
        content: Text(isTurkish
            ? 'Notun gönderilemedi, ama cevabın kaydedildi.'
            : 'The note could not be sent, but your answer was saved.'),
      ));
    }

    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isTurkish = LocaleTextService.isTurkish;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _answer == null ? _askStep(isTurkish) : _noteStep(isTurkish),
        ),
      ),
    );
  }

  List<Widget> _askStep(bool isTurkish) {
    return [
      Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        isTurkish ? 'Kısa bir soru' : 'One quick question',
        style: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        isTurkish
            ? 'KlioAI İngilizceni geliştiriyor mu?'
            : 'Is KlioAI actually improving your English?',
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
      ),
      const SizedBox(height: 20),
      _answerButton(
        key: const ValueKey('feedback-answer-good'),
        label: isTurkish ? 'Evet, işe yarıyor' : 'Yes, it is working',
        color: const Color(0xFF22c55e),
        onTap: () => _choose(FeedbackPromptService.answerGood),
      ),
      const SizedBox(height: 10),
      _answerButton(
        key: const ValueKey('feedback-answer-mixed'),
        label: isTurkish ? 'Kısmen' : 'Somewhat',
        color: const Color(0xFFf59e0b),
        onTap: () => _choose(FeedbackPromptService.answerMixed),
      ),
      const SizedBox(height: 10),
      _answerButton(
        key: const ValueKey('feedback-answer-bad'),
        label: isTurkish ? 'Pek değil' : 'Not really',
        color: const Color(0xFFef4444),
        onTap: () => _choose(FeedbackPromptService.answerBad),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: () async {
            await FeedbackPromptService().recordDismissed();
            if (mounted) Navigator.of(context).pop();
          },
          child: Text(
            isTurkish ? 'Sorma' : 'Do not ask',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          ),
        ),
      ),
    ];
  }

  List<Widget> _noteStep(bool isTurkish) {
    return [
      Text(
        isTurkish ? 'Neyi düzeltmeliyiz?' : 'What should we fix?',
        style: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        isTurkish
            ? 'Tek cümle bile yeter. Bunu okuyan bir kişi var.'
            : 'One sentence is enough. A person reads these.',
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('feedback-note-field'),
        controller: _noteController,
        maxLines: 3,
        maxLength: 500,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: isTurkish
              ? 'Örn: cümleler anlamsız, çeviriler yanlış'
              : 'e.g. the sentences make no sense',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
          counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF8b5cf6)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey('feedback-note-send'),
          onPressed: _sending ? null : _sendNote,
          child: Text(isTurkish ? 'Gönder' : 'Send'),
        ),
      ),
    ];
  }

  Widget _answerButton({
    required Key key,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: key,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          foregroundColor: Colors.white,
        ),
        child: Text(label, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
