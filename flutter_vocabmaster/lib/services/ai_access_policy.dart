int? _toNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool? _toNullableBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  final normalized = value.toString().trim().toLowerCase();
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;
  return null;
}

DateTime? _tryParseDateTime(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }
  return DateTime.tryParse(text);
}

bool hasActiveSubscription(Map<String, dynamic>? userInfo) {
  if (userInfo == null) {
    return false;
  }
  final raw = userInfo['subscriptionEndDate'] ?? userInfo['endDate'];
  if (raw == null) {
    return false;
  }
  final text = raw.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') {
    return false;
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null) {
    return true;
  }
  final now = parsed.isUtc ? DateTime.now().toUtc() : DateTime.now();
  return parsed.isAfter(now);
}

bool hasAiEntitlementSnapshot(Map<String, dynamic>? userInfo) {
  if (userInfo == null) {
    return false;
  }
  return userInfo.containsKey('aiAccessEnabled') ||
      userInfo.containsKey('trialActive') ||
      userInfo.containsKey('planCode') ||
      userInfo.containsKey('aiPlanCode') ||
      userInfo.containsKey('tokenLimit') ||
      userInfo.containsKey('tokensRemaining');
}

bool hasPracticeAccess(Map<String, dynamic>? userInfo) {
  if (userInfo == null) {
    return false;
  }

  final aiAccessEnabled = _toNullableBool(userInfo['aiAccessEnabled']);
  if (aiAccessEnabled != null) {
    return aiAccessEnabled;
  }

  if (_toNullableBool(userInfo['trialActive']) == true) {
    return true;
  }

  final trialDaysRemaining = _toNullableInt(userInfo['trialDaysRemaining']) ?? 0;
  if (trialDaysRemaining > 0) {
    return true;
  }

  if (_toNullableBool(userInfo['isSubscriptionActive']) == true) {
    return true;
  }

  final planCode = (userInfo['planCode'] ?? userInfo['aiPlanCode'])
      ?.toString()
      .trim()
      .toUpperCase();
  if (planCode == 'FREE_TRIAL_7D' ||
      planCode == 'PREMIUM' ||
      planCode == 'PREMIUM_PLUS') {
    return true;
  }

  final tokenLimit = _toNullableInt(userInfo['tokenLimit']) ?? 0;
  final tokensRemaining = _toNullableInt(userInfo['tokensRemaining']) ?? 0;
  if (tokenLimit > 0 || tokensRemaining > 0) {
    return true;
  }

  final trialEligible = _toNullableBool(userInfo['trialEligible']);
  final createdAt = _tryParseDateTime(userInfo['createdAt']);
  if (trialEligible != false && createdAt != null) {
    final now = createdAt.isUtc ? DateTime.now().toUtc() : DateTime.now();
    if (now.difference(createdAt).inDays < 7) {
      return true;
    }
  }

  return hasActiveSubscription(userInfo);
}

