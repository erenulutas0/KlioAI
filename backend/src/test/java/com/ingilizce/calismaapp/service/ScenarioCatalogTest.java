package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The catalog file, checked before it can reach a deploy.
 *
 * <p>The loader never throws -- a scene it cannot play is skipped and logged, so a broken
 * edit costs a scene rather than the server -- which means nothing at runtime would say that
 * a scene had vanished. This is what does. Every field the prompt or the app needs, in every
 * language the app speaks, for every scene.
 */
class ScenarioCatalogTest {

    private static final Set<String> VOICES = Set.of("amy", "ryan", "lessac", "alan", "jenny_dioco", "cori");
    private static final Set<String> LANGUAGES = Set.of("en", "tr", "de", "es", "pt", "it", "fr");
    private static final Set<String> CATEGORIES = Set.of("daily", "travel", "social", "work", "health", "problems");
    private static final Set<String> LEVELS = Set.of("A1", "A2", "B1", "B2", "C1", "C2");

    private final ScenarioCatalog catalog = ScenarioCatalog.load();

    @Test
    @DisplayName("the catalog loads, and nothing in it was skipped")
    void theCatalogLoadsWhole() throws Exception {
        assertNotEquals("none", catalog.version());
        String file = new String(ScenarioCatalog.class.getResourceAsStream("/scenarios/catalog.json").readAllBytes());
        long declared = file.split("\"id\":", -1).length - 1;
        assertEquals(declared, catalog.scenes().size(), "a scene in the file was skipped as unplayable");
        assertTrue(catalog.scenes().size() >= 20);
    }

    @Test
    @DisplayName("every scene the app has ever sent is still here")
    void everySceneTheAppHasEverSentIsStillHere() {
        // Saved conversations and every build before the catalog send these ids. One missing
        // would silently turn that scene into free chat.
        for (String id : List.of("cafe_order", "airport_checkin", "hotel_checkin", "small_talk",
                "doctor_visit", "shopping_return", "job_interview_followup", "academic_presentation_qa",
                "disagreement_colleague", "explaining_to_manager")) {
            assertTrue(catalog.find(id).isPresent(), id);
        }
    }

    @Test
    @DisplayName("ids are unique")
    void idsAreUnique() {
        Set<String> ids = new HashSet<>();
        for (ScenarioCatalog.Scene scene : catalog.scenes()) {
            assertTrue(ids.add(scene.id()), "duplicate id " + scene.id());
        }
    }

    @Test
    @DisplayName("every scene has everything the prompt and the app need, in every language")
    void everySceneIsComplete() {
        for (ScenarioCatalog.Scene scene : catalog.scenes()) {
            String id = scene.id();
            assertTrue(CATEGORIES.contains(scene.category()), id + ": category " + scene.category());
            assertTrue(VOICES.contains(scene.voice()), id + ": no Piper voice called " + scene.voice());
            assertTrue(LEVELS.contains(scene.minLevel()), id + ": level " + scene.minLevel());
            assertFalse(scene.icon() == null || scene.icon().isBlank(), id + ": icon");
            // The header shows the character; the model is told who it is by the persona.
            assertTrue(scene.persona().contains(scene.character()),
                    id + ": the persona never names " + scene.character());
            assertTrue(scene.openings().size() >= 2, id + ": fewer than two openings");
            for (String opening : scene.openings()) {
                assertTrue(opening.length() > 15, id + ": opening too short to start a scene: " + opening);
            }
            assertTrue(scene.rules().size() >= 3, id + ": rules");
            assertTrue(scene.examples().size() >= 2, id + ": examples");
            assertTrue(scene.twists().size() >= 3, id + ": fewer than three complications");
            for (String language : LANGUAGES) {
                assertFalse(scene.title().getOrDefault(language, "").isBlank(), id + ": no " + language + " title");
                assertFalse(scene.goal().getOrDefault(language, "").isBlank(), id + ": no " + language + " goal");
            }
        }
    }

    @Test
    @DisplayName("no goal is the English one pasted into another language")
    void goalsAreTranslated() {
        // Not proof of a translation, but a copy of the English is the likely slip, and a
        // Turkish learner handed an English goal on the one card meant to orient them is lost.
        for (ScenarioCatalog.Scene scene : catalog.scenes()) {
            for (String language : LANGUAGES) {
                if (!language.equals("en")) {
                    assertNotEquals(scene.goal().get("en"), scene.goal().get(language),
                            scene.id() + ": the " + language + " goal is the English one");
                }
            }
        }
    }

    @Test
    @DisplayName("complications are dealt, never written into the rules as well")
    void noRuleRaisesAComplicationOfItsOwn() {
        // The old rules said "raise one small complication". With one dealt per conversation,
        // a rule saying the same would make it two, and the scene would pile up problems.
        for (ScenarioCatalog.Scene scene : catalog.scenes()) {
            for (String rule : scene.rules()) {
                assertFalse(rule.toLowerCase(Locale.ROOT).contains("complication"), scene.id() + ": " + rule);
                assertFalse(rule.toLowerCase(Locale.ROOT).contains("obstacle"), scene.id() + ": " + rule);
            }
        }
    }

    @Test
    @DisplayName("a language the catalog lacks falls back to English")
    void titlesFallBackToEnglish() {
        ScenarioCatalog.Scene cafe = catalog.find("cafe_order").orElseThrow();
        assertEquals("Ordering coffee", cafe.titleIn("ja"));
        assertEquals("Ordering coffee", cafe.titleIn(null));
        assertEquals("Kahve siparişi", cafe.titleIn("TR"));
    }

    @Test
    @DisplayName("the opening a variant picks is the one the app will pick")
    void openingsFollowTheVariantModuloTheCount() {
        // The app picks openings[variant % length] on its side; the server must agree, or the
        // model is told it opened with a line the learner never saw.
        ScenarioCatalog.Scene cafe = catalog.find("cafe_order").orElseThrow();
        for (int variant = 0; variant < 10; variant++) {
            assertEquals(cafe.openings().get(variant % cafe.openings().size()), cafe.openingFor(variant));
        }
    }

    @Test
    @DisplayName("a scene missing what it needs is not played")
    void anIncompleteSceneIsNotPlayable() {
        ScenarioCatalog.Scene cafe = catalog.find("cafe_order").orElseThrow();
        ScenarioCatalog.Scene noTwists = new ScenarioCatalog.Scene(cafe.id(), cafe.category(), cafe.icon(),
                cafe.minLevel(), cafe.character(), cafe.voice(), cafe.persona(), cafe.openings(), cafe.rules(),
                cafe.context(), cafe.examples(), List.of(), cafe.title(), cafe.goal());
        assertTrue(ScenarioCatalog.isPlayable(cafe));
        assertFalse(ScenarioCatalog.isPlayable(noTwists));
        assertFalse(ScenarioCatalog.isPlayable(null));
    }
}
