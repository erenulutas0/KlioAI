class SpeechTranscriptPolicy {
  static const double defaultConfidenceThreshold = 0.65;

  const SpeechTranscriptPolicy._();

  static bool canAutoSend({
    required String transcript,
    required bool finalResultReceived,
    required double confidence,
    double confidenceThreshold = defaultConfidenceThreshold,
  }) {
    if (transcript.trim().isEmpty) {
      return false;
    }

    return !needsReview(
      finalResultReceived: finalResultReceived,
      confidence: confidence,
      confidenceThreshold: confidenceThreshold,
    );
  }

  static bool needsReview({
    required bool finalResultReceived,
    required double confidence,
    double confidenceThreshold = defaultConfidenceThreshold,
  }) {
    if (!finalResultReceived) {
      return true;
    }

    return hasUsableConfidence(confidence) && confidence < confidenceThreshold;
  }

  static bool hasUsableConfidence(double confidence) {
    return confidence > 0 && confidence <= 1;
  }

  static int? confidencePercent(double confidence) {
    if (!hasUsableConfidence(confidence)) {
      return null;
    }

    final value = (confidence * 100).round();
    return value.clamp(0, 100).toInt();
  }
}
