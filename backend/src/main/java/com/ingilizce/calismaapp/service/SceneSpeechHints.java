package com.ingilizce.calismaapp.service;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * The words a scene is about, as a spelling hint for the speech recogniser.
 *
 * <p>Whisper takes a {@code prompt}, and the one thing it is for is vocabulary and proper
 * nouns -- see the warning on {@code GroqSpeechToTextService.prompt} about what happens when
 * prose goes in there instead. The learner's own saved words already go in. A scene's do not,
 * and a scene is precisely where the learner is about to say words they would never otherwise
 * say: the waiter is Luca, the dish is the lasagne, the twist is an ingredient they have to
 * name. Those are the words a recogniser mishears.
 *
 * <p>Taken from the scene's own text rather than written out per scene, so a new scene in the
 * catalog is covered the day it is added and nothing can drift out of step with it. Short and
 * very common words are dropped: the hint is a bias and not a dictionary, and a list padded
 * with "evening" and "something" spreads the model's attention over words the learner was
 * always going to be understood saying.
 */
final class SceneSpeechHints {

    /**
     * How many words are worth taking from one scene.
     *
     * <p>The learner's own vocabulary follows these in the same hint, under a cap of its own,
     * and what is at the front is what counts. A dozen leaves the scene's distinctive words
     * first without crowding the deck out.
     */
    static final int MAX_HINTS = 12;

    /** Shorter than this and a word is almost always one of the ones below anyway. */
    private static final int MIN_WORD_CHARS = 4;

    /**
     * The words that carry no scene in them.
     *
     * <p>Not a general stop list -- it is the frequent English a tutor scene is written in.
     * Anything here would be recognised without help, and every entry that stays out of the
     * hint leaves room for one that would not be.
     */
    private static final Set<String> TOO_COMMON = Set.of(
            "about", "after", "again", "already", "also", "always", "another", "anything",
            "anyone", "back", "because", "been", "before", "being", "bring", "brings", "came",
            "come", "comes", "coming", "could", "does", "doing", "done", "down", "each",
            "else", "even", "ever", "every", "everything", "find", "first", "from", "front",
            "gets", "give", "gives", "going", "good", "great", "hard", "have", "having",
            "hear", "help", "here", "into", "just", "keep", "kind", "know", "last", "late",
            "leave", "less", "life", "like", "little", "long", "look", "looking", "made",
            "make", "makes", "many", "maybe", "mean", "might", "more", "most", "much",
            "must", "need", "needs", "never", "next", "nice", "nothing", "only", "open",
            "other", "over", "part", "people", "person", "place", "please", "plenty",
            "point", "really", "right", "said", "same", "says", "seem", "seems", "sees",
            "should", "since", "some", "something", "sorry", "sound", "sounds", "start",
            "still", "such", "sure", "take", "takes", "tell", "than", "that", "their",
            "them", "then", "there", "these", "they", "thing", "things", "think", "this",
            "those", "through", "time", "today", "tonight", "took", "turn", "very", "wait",
            "want", "wants", "well", "were", "what", "when", "where", "which", "while",
            "will", "with", "without", "word", "words", "work", "would", "your", "yours",
            "evening", "morning", "afternoon", "everyone", "somebody", "themselves",
            "clearly", "explain", "explains", "friendly", "quick", "quickly", "small",
            "suggest", "wrong", "true", "full", "busy", "easy", "free", "half", "hour",
            "hours", "minute", "minutes", "twenty", "thirty", "week", "year", "years");

    private static final Pattern NOT_A_WORD = Pattern.compile("[^A-Za-z'-]+");

    private SceneSpeechHints() {
    }

    /** The scene's distinctive words, the character's name first. Never null. */
    static List<String> of(ScenarioCatalog.Scene scene) {
        if (scene == null) {
            return List.of();
        }
        List<String> hints = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        // The name is the one word the learner will certainly say and the recogniser has
        // never seen, so it goes first whatever else fits -- and it skips the filters below,
        // because Tom, Ben and Sam are three letters long and were being dropped as noise.
        addName(hints, seen, scene.character());
        for (String example : scene.examples()) {
            addWords(hints, seen, example);
        }
        for (String twist : scene.twists()) {
            addWords(hints, seen, twist);
        }
        addWords(hints, seen, scene.context());
        return List.copyOf(hints.subList(0, Math.min(hints.size(), MAX_HINTS)));
    }

    /** The character's name, whatever its length: a name is never the word to leave out. */
    private static void addName(List<String> hints, Set<String> seen, String name) {
        if (name == null || name.isBlank()) {
            return;
        }
        for (String raw : NOT_A_WORD.split(name)) {
            String word = raw.trim();
            if (!word.isEmpty() && seen.add(word.toLowerCase(Locale.ROOT))) {
                hints.add(word);
            }
        }
    }

    private static void addWords(List<String> hints, Set<String> seen, String text) {
        if (text == null || text.isBlank()) {
            return;
        }
        for (String raw : NOT_A_WORD.split(text)) {
            String word = raw.trim();
            String key = word.toLowerCase(Locale.ROOT);
            if (word.length() < MIN_WORD_CHARS || TOO_COMMON.contains(key)) {
                continue;
            }
            // "That's", "we're", "I'll", "kitchen's": a contraction or a possessive is an
            // inflection of a word the recogniser already has. The hint is for the spellings
            // it does not, and every one of these was taking a slot from one of those.
            if (word.contains("'")) {
                continue;
            }
            // Case-insensitively, so "Menu" at the start of a line and "menu" inside one are
            // one hint and not two of the twelve.
            if (seen.add(key)) {
                hints.add(word);
            }
        }
    }
}
