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
     */
    public record ShelvedBook(
            String slug,
            String title,
            String author,
            String level,
            String source,
            String resource,
            String publicDomainBasis) {
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
                    "Potter died in 1943; published 1902."),
            new ShelvedBook(
                    "aesops-fables",
                    "Aesop's Fables",
                    "Aesop",
                    "A2",
                    "gutenberg:21",
                    "/books/aesops-fables.txt",
                    "Ancient text; this translation was published in 1912."),
            new ShelvedBook(
                    "happy-prince",
                    "The Happy Prince and Other Tales",
                    "Oscar Wilde",
                    "B1",
                    "gutenberg:902",
                    "/books/happy-prince.txt",
                    "Wilde died in 1900."),
            new ShelvedBook(
                    "sherlock-adventures",
                    "The Adventures of Sherlock Holmes",
                    "Arthur Conan Doyle",
                    "B1",
                    "gutenberg:1661",
                    "/books/sherlock-adventures.txt",
                    "Doyle died in 1930."),
            new ShelvedBook(
                    "jekyll-and-hyde",
                    "The Strange Case of Dr Jekyll and Mr Hyde",
                    "Robert Louis Stevenson",
                    "B2",
                    "gutenberg:43",
                    "/books/jekyll-and-hyde.txt",
                    "Stevenson died in 1894."),
            new ShelvedBook(
                    "heart-of-darkness",
                    "Heart of Darkness",
                    "Joseph Conrad",
                    "C1",
                    "gutenberg:219",
                    "/books/heart-of-darkness.txt",
                    "Conrad died in 1924."));

    /** Reads a shelved book's text out of the jar. */
    public static String readText(ShelvedBook book) throws IOException {
        try (InputStream in = BookLibrary.class.getResourceAsStream(book.resource())) {
            if (in == null) {
                throw new IOException("shelved book missing from the build: " + book.resource());
            }
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
