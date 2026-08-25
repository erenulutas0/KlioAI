package com.ingilizce.calismaapp.service;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * The shelf that ships with the app.
 *
 * <p>Every title here is a work whose copyright has expired, carried in the
 * jar rather than fetched at import time. That is deliberate: the exact text a
 * learner reads is then in version control, an import does not depend on
 * anyone else's website being up, and the provenance of any sentence can be
 * answered years later by looking at the file it came from.
 *
 * <p>Levels are a reading-difficulty judgement, not a claim about the author.
 * They order the shelf so a learner meets Peter Rabbit before Conrad.
 */
public final class BookLibrary {

    private BookLibrary() {
    }

    /**
     * One shelved title.
     *
     * @param publicDomainBasis why this text is free to use — recorded next to
     *                          the book rather than in a note somewhere, because
     *                          it is the question that matters most about it
     * @param startsAt          text on the first line of the actual book, used
     *                          to cut off the front matter above it
     * @param endsAt            text on the first line of whatever follows the
     *                          book — an index, a printer's colophon — or blank
     *                          when the book runs to the end of the file
     */
    public record ShelvedBook(
            String slug,
            String title,
            String author,
            String level,
            String source,
            String resource,
            String publicDomainBasis,
            String startsAt,
            String endsAt) {
    }

    /** In reading order: easiest first. */
    public static final List<ShelvedBook> BOOKS = List.of(
            new ShelvedBook(
                    "peter-rabbit",
                    "The Tale of Peter Rabbit",
                    "Beatrix Potter",
                    "A1",
                    "gutenberg:14838",
                    "/books/peter-rabbit.txt",
                    "Potter died in 1943; published 1902.",
                    "Once upon a time there were four little Rabbits",
                    ""),
            new ShelvedBook(
                    "aesops-fables",
                    "Aesop's Fables",
                    "Aesop",
                    "A2",
                    "gutenberg:21",
                    "/books/aesops-fables.txt",
                    "Ancient text; this translation was published in 1912.",
                    "A LION was awakened from sleep by a Mouse",
                    "FOOTNOTES"),
            new ShelvedBook(
                    "happy-prince",
                    "The Happy Prince and Other Tales",
                    "Oscar Wilde",
                    "B1",
                    "gutenberg:902",
                    "/books/happy-prince.txt",
                    "Wilde died in 1900.",
                    "HIGH above the city",
                    "Printed by BALLANTYNE"),
            new ShelvedBook(
                    "sherlock-adventures",
                    "The Adventures of Sherlock Holmes",
                    "Arthur Conan Doyle",
                    "B1",
                    "gutenberg:1661",
                    "/books/sherlock-adventures.txt",
                    "Doyle died in 1930.",
                    "To Sherlock Holmes she is always",
                    ""),
            new ShelvedBook(
                    "jekyll-and-hyde",
                    "The Strange Case of Dr Jekyll and Mr Hyde",
                    "Robert Louis Stevenson",
                    "B2",
                    "gutenberg:43",
                    "/books/jekyll-and-hyde.txt",
                    "Stevenson died in 1894.",
                    "Mr. Utterson the lawyer was a man of a rugged countenance",
                    ""),
            new ShelvedBook(
                    "heart-of-darkness",
                    "Heart of Darkness",
                    "Joseph Conrad",
                    "C1",
                    "gutenberg:219",
                    "/books/heart-of-darkness.txt",
                    "Conrad died in 1924.",
                    "The Nellie, a cruising yawl, swung to her anchor",
                    ""));

    /**
     * Reads a shelved book out of the jar, cut down to the book itself.
     *
     * <p>A Gutenberg file is not only the book. Around it sit a title page, a
     * publisher's address, a printing history, a table of contents, and often a
     * long alphabetical index at the back. Aesop's front and back lists are
     * thirteen per cent of that file. Segmented, they become thousands of
     * "sentences" that are lists of titles: paid for once, then shown to a
     * learner as something to read.
     *
     * <p>The boundaries are recorded per book rather than guessed by rule. Six
     * hand-picked books can have their first and last lines read once by a
     * person; a general front-matter detector would be a guess that fails
     * silently on the seventh book, and silently is the worst way for this to
     * fail — nobody reports a chapter that was never shown.
     */
    public static String readText(ShelvedBook book) throws IOException {
        return trimToBook(readRaw(book), book);
    }

    /** The file exactly as it ships, boundaries and all. */
    public static String readRaw(ShelvedBook book) throws IOException {
        try (InputStream in = BookLibrary.class.getResourceAsStream(book.resource())) {
            if (in == null) {
                throw new IOException("shelved book missing from the build: " + book.resource());
            }
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    /**
     * Cuts the raw file down to the book, on whole-line boundaries.
     *
     * <p>Cutting at the line rather than at the marker matters: these files are
     * hard-wrapped to about seventy columns, so a marker chosen from the middle
     * of a first sentence would otherwise behead it.
     *
     * <p>{@code startsAt} is matched at its first occurrence and {@code endsAt}
     * at its last, because back matter repeats what the front matter said: a
     * table of contents at the front names the same index heading that appears
     * again at the back.
     *
     * <p>A marker that does not match leaves that end of the book alone. That is
     * the safe direction to fail — some front matter reaches a reader, rather
     * than a book being silently truncated to nothing.
     */
    static String trimToBook(String raw, ShelvedBook book) {
        String text = raw;

        String endsAt = book.endsAt();
        if (endsAt != null && !endsAt.isBlank()) {
            int found = text.lastIndexOf(endsAt);
            if (found > 0) {
                text = text.substring(0, startOfLine(text, found));
            }
        }

        String startsAt = book.startsAt();
        if (startsAt != null && !startsAt.isBlank()) {
            int found = text.indexOf(startsAt);
            if (found >= 0) {
                text = text.substring(startOfLine(text, found));
            }
        }

        return text;
    }

    private static int startOfLine(String text, int index) {
        return text.lastIndexOf('\n', index) + 1;
    }
}
