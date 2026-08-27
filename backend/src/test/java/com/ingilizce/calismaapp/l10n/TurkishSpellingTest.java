package com.ingilizce.calismaapp.l10n;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Turkish that reaches a learner from the server, spelled the way Turkish is
 * spelled.
 *
 * <p>Almost every string in this module is English — prompts, log lines, error
 * codes — so the Turkish ones are easy to stop reading. Five had lost their
 * diacritics: the message shown when AI is switched off ("AI ozellikleri su an
 * pasif"), and the fallbacks a learner sees when an evaluation fails ("Lutfen
 * yazinizi tekrar degerlendirin"). That is the worst place for it — the app is
 * already failing, and the apology is misspelled.
 *
 * <p>The client carries the same three checks over a much larger corpus. This
 * is the smaller half, and being smaller is how it stayed unread.
 */
class TurkishSpellingTest {

    private static final String LOWER = "çğıöşü";
    private static final String UPPER = "ÇĞİÖŞÜ";
    private static final String BACK = "aıou";
    private static final String FRONT = "eiöü";

    /**
     * Words that break vowel harmony and are still correct: borrowings, mostly.
     *
     * <p>This is the exception list, not a list of the words the test knows
     * about. Anything absent from it that mixes the two vowel sets fails, so a
     * newly added bare word has to be either fixed or written down with a
     * reason. A list in the other direction — the words we remembered — is what
     * the client used to have, and it passed for months while forty words were
     * spelled two ways at once.
     */
    private static final Set<String> BORROWED = Set.of(
            "aktif", "aktivasyon", "azimli", "biraz", "cihaz", "dakika", "deletion", "demo",
            "dikkatsiz", "hafif", "hangi", "insan", "istasyonun", "kitap", "modern",
            "pasif", "politika", "porsiyonlar", "premium", "probleme", "samimi", "takip", "tarih",
            "tatil", "trafik", "trial", "vardiyadan", "video");

    /** Turkish words common enough to identify a string as Turkish at all. */
    private static final Set<String> MARKERS = Set.of(
            "ve", "bir", "bu", "ile", "için", "icin", "daha", "çok", "cok", "ama", "veya",
            "gibi", "olarak", "yok", "var", "kelime", "cümle", "cumle", "lütfen", "lutfen",
            "tekrar", "deneyin", "hata", "bulunamadı", "bulunamadi", "geçersiz", "gecersiz",
            "kullanıcı", "kullanici", "başarılı", "basarili", "oturum", "şu", "su", "sonra",
            "önce", "once", "türkçe", "turkce", "ingilizce", "anlamı", "anlami");

    /**
     * A literal that stays on one line.
     *
     * <p>Letting it span lines is not a small mistake: the first version did,
     * and every stretch of comment sitting between two unrelated quotes came
     * back as a string. It reported five conflicts, all of them prose from
     * comments, and every one was a false alarm.
     */
    private static final Pattern LITERAL = Pattern.compile("\"([^\"\\\\\n\r]*)\"");

    private static final Pattern WORD = Pattern.compile("[A-Za-z" + LOWER + UPPER + "]+");

    /**
     * Turkish's own casing, which differs from every other language's: i
     * uppercases to İ and I lowercases to ı.
     *
     * <p>Applying it to English is how an earlier version of this scan produced
     * "ıdentity" and "ımportant" and called them misspellings — which is why
     * only strings that {@link #looksTurkish} are ever folded.
     */
    private static String turkishLower(String s) {
        return s.replace('İ', 'i').replace('I', 'ı').toLowerCase();
    }

    private static String fold(String s) {
        StringBuilder out = new StringBuilder();
        for (char c : turkishLower(s).toCharArray()) {
            int at = LOWER.indexOf(c);
            out.append(at < 0 ? c : "cgiosu".charAt(at));
        }
        return out.toString();
    }

    private static List<String> words(String s) {
        List<String> out = new ArrayList<>();
        Matcher m = WORD.matcher(s);
        while (m.find()) {
            out.add(m.group());
        }
        return out;
    }

    private static boolean looksTurkish(String s) {
        for (char c : s.toCharArray()) {
            if (LOWER.indexOf(c) >= 0 || UPPER.indexOf(c) >= 0) {
                return true;
            }
        }
        int seen = 0;
        for (String word : words(s)) {
            if (MARKERS.contains(turkishLower(word))) {
                seen++;
            }
        }
        return seen >= 2;
    }

    /** Every Turkish string literal under src/main, with the file it came from. */
    private static List<Map.Entry<String, String>> turkishStrings() throws IOException {
        List<Map.Entry<String, String>> found = new ArrayList<>();
        try (Stream<Path> tree = Files.walk(Path.of("src", "main"))) {
            for (Path file : tree.filter(Files::isRegularFile).toList()) {
                String name = file.getFileName().toString();
                if (!name.endsWith(".java") && !name.endsWith(".yml") && !name.endsWith(".sql")) {
                    continue;
                }
                Matcher m = LITERAL.matcher(Files.readString(file));
                while (m.find()) {
                    if (looksTurkish(m.group(1))) {
                        found.add(Map.entry(name, m.group(1)));
                    }
                }
            }
        }
        // Without this, every assertion below passes just as happily when the
        // scan stops matching — the one failure a guard cannot report on itself.
        assertTrue(found.size() > 100,
                "the scan found " + found.size() + " Turkish strings, so it is measuring "
                        + "nothing: the literal pattern or the walk has stopped matching");
        return found;
    }

    @Test
    @DisplayName("one Turkish word is spelled one way")
    void oneSpellingPerWord() throws IOException {
        Map<String, Map<String, String>> spellings = new TreeMap<>();
        for (Map.Entry<String, String> entry : turkishStrings()) {
            for (String word : words(entry.getValue())) {
                if (word.length() < 3) {
                    continue;
                }
                spellings.computeIfAbsent(fold(word), key -> new TreeMap<>())
                        .putIfAbsent(turkishLower(word), entry.getKey());
            }
        }

        List<String> offenders = new ArrayList<>();
        spellings.forEach((folded, variants) -> {
            if (variants.size() > 1) {
                offenders.add("  " + folded + ": " + variants);
            }
        });
        assertTrue(offenders.isEmpty(),
                "The same Turkish word is spelled more than one way:\n"
                        + String.join("\n", offenders));
    }

    @Test
    @DisplayName("no Turkish word quietly drops its diacritics")
    void noBareWords() throws IOException {
        // Two rules about the language, for the words the comparison above
        // cannot reach: the ones written bare in every place they appear, which
        // look perfectly consistent to it. Between two vowels Turkish g is
        // almost always ğ, and a native word keeps to one of the two vowel
        // sets, so a word that mixes them has usually had its ı, ö or ü
        // flattened.
        Map<String, String> suspects = new TreeMap<>();
        for (Map.Entry<String, String> entry : turkishStrings()) {
            for (String raw : words(entry.getValue())) {
                String word = turkishLower(raw);
                if (word.length() < 4 || !fold(word).equals(word) || BORROWED.contains(word)) {
                    continue;
                }
                if (looksBare(word)) {
                    suspects.putIfAbsent(word, entry.getKey());
                }
            }
        }

        Set<String> lines = new TreeSet<>();
        suspects.forEach((word, where) -> lines.add("  " + word + "   (" + where + ")"));
        assertTrue(lines.isEmpty(),
                "These read as Turkish with the diacritics left out. Fix the word, or add it "
                        + "to BORROWED if it is a loanword:\n" + String.join("\n", lines));
    }

    private static boolean looksBare(String word) {
        // -abil-/-ebil- is "bilmek" fused onto another verb, and the seam is a
        // real break in harmony: "yapabilir" is spelled exactly like that. A
        // rule rather than a list, because the forms are endless — olabilir,
        // gelebilirsin, uyarlayabilir.
        if (word.contains("abil") || word.contains("ebil")) {
            return false;
        }
        // The present-tense -Iyor is half invariant: its first vowel harmonises
        // (aranıyor, gerekiyor) but the o never does. Dropping the "yor" leaves
        // the part that does have to agree — which keeps "gerekiyor" out of the
        // results without also excusing "araniyor", whose stem still mixes.
        if (word.endsWith("yor")) {
            word = word.substring(0, word.length() - 3);
        }
        Set<Character> vowels = new HashSet<>();
        boolean back = false;
        boolean front = false;
        String anyVowel = BACK + FRONT;
        for (int i = 0; i < word.length(); i++) {
            char c = word.charAt(i);
            if (BACK.indexOf(c) >= 0) {
                back = true;
                vowels.add(c);
            } else if (FRONT.indexOf(c) >= 0) {
                front = true;
                vowels.add(c);
            }
            boolean between = i > 0 && i + 1 < word.length()
                    && anyVowel.indexOf(word.charAt(i - 1)) >= 0
                    && anyVowel.indexOf(word.charAt(i + 1)) >= 0;
            if (c == 'g' && between) {
                return true;
            }
        }
        // a and e are the two vowels no diacritic can move, so a word holding
        // both cannot be repaired by adding marks: it is a borrowing, and the
        // harmony rule has nothing to say about it.
        return back && front && !(vowels.contains('a') && vowels.contains('e'));
    }

    @Test
    @DisplayName("the exception list stays honest")
    void exceptionsAreStillInUse() throws IOException {
        // An exception list that outlives the strings it excused decays into
        // the enumerated list this test exists to avoid.
        Set<String> seen = new HashSet<>();
        for (Map.Entry<String, String> entry : turkishStrings()) {
            for (String word : words(entry.getValue())) {
                seen.add(turkishLower(word));
            }
        }
        Set<String> stale = new TreeSet<>(BORROWED);
        stale.removeAll(seen);
        assertTrue(stale.isEmpty(),
                "BORROWED excuses words no Turkish string uses any more: " + stale);
    }
}
