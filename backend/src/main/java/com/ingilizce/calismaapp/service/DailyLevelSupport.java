package com.ingilizce.calismaapp.service;

import java.util.List;
import java.util.Locale;

public final class DailyLevelSupport {

    private static final List<String> SUPPORTED_LEVELS = List.of("A1", "A2", "B1", "B2", "C1", "C2");

    private DailyLevelSupport() {
    }

    public static List<String> supportedLevels() {
        return SUPPORTED_LEVELS;
    }

    public static String normalizeLevel(String rawLevel) {
        if (rawLevel == null || rawLevel.isBlank()) {
            return "B1";
        }

        String normalized = rawLevel.trim().toUpperCase(Locale.ROOT);
        if (SUPPORTED_LEVELS.contains(normalized)) {
            return normalized;
        }
        return "B1";
    }

    public static String readingBandForLevel(String level) {
        String normalized = normalizeLevel(level);
        return switch (normalized) {
            case "A1", "A2", "B1", "B2", "C1", "C2" -> normalized;
            default -> "B1";
        };
    }

    public static String writingWordCountForLevel(String level) {
        String normalized = normalizeLevel(level);
        return switch (normalized) {
            case "A1" -> "40-70";
            case "A2" -> "60-90";
            case "B1" -> "90-130";
            case "B2" -> "120-170";
            case "C1" -> "160-220";
            case "C2" -> "200-260";
            default -> "90-130";
        };
    }
}
