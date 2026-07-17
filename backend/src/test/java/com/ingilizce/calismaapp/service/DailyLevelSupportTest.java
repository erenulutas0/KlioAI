package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class DailyLevelSupportTest {

    @Test
    void supportedLevels_shouldExposeCefrLevelsInOrder() {
        assertEquals(List.of("A1", "A2", "B1", "B2", "C1", "C2"),
                DailyLevelSupport.supportedLevels());
    }

    @Test
    void normalizeLevel_shouldAcceptCaseAndWhitespace() {
        assertEquals("A1", DailyLevelSupport.normalizeLevel(" a1 "));
        assertEquals("B2", DailyLevelSupport.normalizeLevel("b2"));
        assertEquals("C2", DailyLevelSupport.normalizeLevel(" C2 "));
    }

    @Test
    void normalizeLevel_shouldFallbackToB1ForBlankOrUnsupportedValues() {
        assertEquals("B1", DailyLevelSupport.normalizeLevel(null));
        assertEquals("B1", DailyLevelSupport.normalizeLevel(""));
        assertEquals("B1", DailyLevelSupport.normalizeLevel("beginner"));
        assertEquals("B1", DailyLevelSupport.normalizeLevel("D1"));
    }

    @Test
    void readingBandForLevel_shouldReturnNormalizedLevel() {
        assertEquals("A2", DailyLevelSupport.readingBandForLevel("a2"));
        assertEquals("B1", DailyLevelSupport.readingBandForLevel("unknown"));
    }

    @Test
    void writingWordCountForLevel_shouldMapEachCefrLevel() {
        assertEquals("40-70", DailyLevelSupport.writingWordCountForLevel("A1"));
        assertEquals("60-90", DailyLevelSupport.writingWordCountForLevel("A2"));
        assertEquals("90-130", DailyLevelSupport.writingWordCountForLevel("B1"));
        assertEquals("120-170", DailyLevelSupport.writingWordCountForLevel("B2"));
        assertEquals("160-220", DailyLevelSupport.writingWordCountForLevel("C1"));
        assertEquals("200-260", DailyLevelSupport.writingWordCountForLevel("C2"));
        assertEquals("90-130", DailyLevelSupport.writingWordCountForLevel("invalid"));
    }
}
