import 'dart:async';

import 'package:flutter/material.dart';

import '../frontend_newest/theme/nf_tokens.dart';
import '../frontend_newest/widgets/nf_rating_card.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/feedback_prompt_service.dart';
import '../services/in_app_review_service.dart';
import '../services/rating_prompt_service.dart';

/// One question, after a session that went well: how was it, out of five.
///
/// The app can measure that somebody opened it, finished a review and earned XP. It cannot
/// measure whether the sentences made sense or whether any of it is teaching them anything
/// -- it spent three months serving hardcoded template sentences while every request was
/// logged as a success. The only instrument that catches that is a person, and only if
/// being asked costs them one tap.
///
/// This used to be three answers, and only an unhappy one ever reached the server: "yes, it
/// is working" stayed on the phone. So the server heard complaints and nothing to set them
/// against. Now every answer is sent (see FeatureRatingController), with a note asked for
/// when the stars are low -- a number says something is wrong, the note says what -- and
/// the store's own rating sheet is shown only after five stars.
class FeedbackPromptSheet extends StatefulWidget {
  const FeedbackPromptSheet._({required this.completions, required this.feature});

  final int completions;

  /// What is being rated: READING, WRITING, SESSION, or PRACTICE when the caller does not say.
  final String feature;

  /// Shows the sheet if it is due. Returns without doing anything if it is not.
  ///
  /// Safe to call at the end of any session: the services own the decision. Two clocks
  /// apply -- this sheet's own, which waits for three finished practices, and the one every
  /// rating question shares, so the tutor and this sheet cannot both ask on the same day.
  static Future<void> maybeShow(BuildContext context, {String feature = 'PRACTICE'}) async {
    final FeedbackPromptService service = FeedbackPromptService();
    final int completions = await service.completions();
    if (!await service.shouldAsk(completions)) {
      return;
    }
    final RatingPromptService prompts = RatingPromptService();
    if (!await prompts.shouldAsk(feature)) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await prompts.recordAsked(feature);
    if (!context.mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedbackPromptSheet._(completions: completions, feature: feature),
    );
  }

  @override
  State<FeedbackPromptSheet> createState() => _FeedbackPromptSheetState();
}

class _FeedbackPromptSheetState extends State<FeedbackPromptSheet> {
  late final NfRatingController _rating = NfRatingController(onSubmit: _submit);

  // Read while the sheet is on screen: a rating flushed from dispose() can no longer look
  // anything up through its context.
  String _locale = 'en';
  Timer? _closeTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locale = Localizations.localeOf(context).languageCode;
  }

  @override
  void initState() {
    super.initState();
    _rating.addListener(_onRatingChanged);
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _rating.removeListener(_onRatingChanged);
    // Swiped away with low stars chosen and no note: the stars were still an answer.
    _rating.flush();
    _rating.dispose();
    super.dispose();
  }

  void _onRatingChanged() {
    if (_rating.stage == NfRatingStage.thanks && _closeTimer == null) {
      // Long enough to read "thank you"; short enough not to be in the way.
      _closeTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  Future<void> _submit(int stars, String? note) async {
    final FeedbackPromptService service = FeedbackPromptService();
    // The old three answers, kept so this sheet's own schedule keeps working: a happy answer
    // ends the asking, an unhappy one is revisited much later.
    await service.recordAnswer(
      stars >= 4
          ? FeedbackPromptService.answerGood
          : stars == 3
              ? FeedbackPromptService.answerMixed
              : FeedbackPromptService.answerBad,
      widget.completions,
    );
    await RatingPromptService().recordAnswered();

    final String? version = await nfAppVersion();
    // Side by side: the store's sheet waits for the learner, and a rating queued behind it
    // is lost if they leave the app from there.
    await Future.wait(<Future<void>>[
      ApiService().submitFeatureRating(
        feature: widget.feature,
        stars: stars,
        note: note,
        locale: _locale,
        appVersion: version,
        context: <String, Object?>{'completions': widget.completions},
      ),
      if (nfRatingEarnsStoreReview(stars)) _requestStoreReviewIfEligible(),
    ]);
  }

  static Future<void> _requestStoreReviewIfEligible() async {
    final InAppReviewService review = InAppReviewService();
    if (await review.isEligibleForStorePrompt()) {
      await review.requestStoreReview();
    }
  }

  Future<void> _dontAskAgain() async {
    await FeedbackPromptService().recordDismissed();
    await RatingPromptService().recordOptedOut();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final NfTokens t = NfTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(NfSpace.s16, NfSpace.s12, NfSpace.s16, NfSpace.s22),
        decoration: BoxDecoration(
          color: t.ground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(NfRadius.card)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: NfSpace.s12),
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(NfRadius.pill),
                ),
              ),
              NfRatingCard(
                controller: _rating,
                title: context.tr('rating.practice.title'),
                onDontAskAgain: () => unawaited(_dontAskAgain()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
