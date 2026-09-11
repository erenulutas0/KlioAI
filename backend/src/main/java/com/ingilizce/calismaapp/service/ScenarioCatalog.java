package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.InputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * The roleplay scenes, read from {@code scenarios/catalog.json}.
 *
 * <p>They used to be code: six as a table in ChatbotService, four as twenty-line blocks of
 * their own, and the app kept a copy of eight of them to draw its chips -- two of the ten
 * never reached the app at all. Adding a scene meant a server deploy and an app release.
 * The catalog is data now: the server builds the prompt from it and serves the half a
 * learner sees, in their language, to the app.
 *
 * <p>Each scene also carries what made the old table read like a costume rather than a
 * place: the learner's goal, several ways to open, and complications -- one is dealt per
 * conversation, so the same cafe is not the same conversation twice.
 */
public final class ScenarioCatalog {

  private static final Logger log = LoggerFactory.getLogger(ScenarioCatalog.class);
  private static final String RESOURCE = "/scenarios/catalog.json";
  private static volatile ScenarioCatalog bundled;

  /** One scene. The lists are never empty: see {@link #isPlayable}. */
  public record Scene(String id, String category, String icon, String minLevel, String character,
      String voice, String persona, List<String> openings, List<String> rules, String context,
      List<String> examples, List<String> twists, Map<String, String> title,
      Map<String, String> goal) {

    public String titleIn(String language) {
      return localized(title, language);
    }

    public String goalIn(String language) {
      return localized(goal, language);
    }

    /** The opening for [variant]: the variant modulo the count, which the app computes too. */
    public String openingFor(int variant) {
      return openings.get(Math.floorMod(variant, openings.size()));
    }

    /**
     * The complication for [variant]. Not the opening's index, so which opening and which
     * complication a conversation gets vary independently of each other.
     */
    public String twistFor(int variant) {
      return twists.get(Math.floorMod(Objects.hash(id, variant), twists.size()));
    }

    private static String localized(Map<String, String> texts, String language) {
      String code = language == null ? "en" : language.trim().toLowerCase(Locale.ROOT);
      String text = texts.get(code);
      return text != null && !text.isBlank() ? text : texts.get("en");
    }
  }

  record CatalogFile(List<Scene> scenes) {
  }

  private final List<Scene> scenes;
  private final String version;

  ScenarioCatalog(List<Scene> scenes, String version) {
    this.scenes = List.copyOf(scenes);
    this.version = version;
  }

  /** The catalog shipped with this build, read once. */
  public static ScenarioCatalog bundled() {
    ScenarioCatalog catalog = bundled;
    if (catalog == null) {
      synchronized (ScenarioCatalog.class) {
        catalog = bundled;
        if (catalog == null) {
          catalog = load();
          bundled = catalog;
        }
      }
    }
    return catalog;
  }

  /**
   * Reads the catalog. Never throws: a scene that cannot be played is skipped and logged, and
   * a catalog that cannot be read at all is empty -- every scene then falls back to ordinary
   * chat, which is how an unknown scene has always behaved. ScenarioCatalogTest is what keeps
   * either from reaching a deploy.
   */
  static ScenarioCatalog load() {
    try (InputStream in = ScenarioCatalog.class.getResourceAsStream(RESOURCE)) {
      if (in == null) {
        log.error("No scenario catalog at {}; every scene will be free chat", RESOURCE);
        return new ScenarioCatalog(List.of(), "none");
      }
      byte[] bytes = in.readAllBytes();
      ObjectMapper json = new ObjectMapper()
          .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
      CatalogFile file = json.readValue(bytes, CatalogFile.class);
      List<Scene> playable = new ArrayList<>();
      for (Scene scene : file.scenes() == null ? List.<Scene>of() : file.scenes()) {
        if (isPlayable(scene)) {
          playable.add(scene);
        } else {
          log.error("Skipping scenario '{}': it is missing something it needs to be played",
              scene == null ? null : scene.id());
        }
      }
      String version = HexFormat.of()
          .formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)).substring(0, 12);
      return new ScenarioCatalog(playable, version);
    } catch (Exception e) {
      log.error("Could not read the scenario catalog; every scene will be free chat", e);
      return new ScenarioCatalog(List.of(), "none");
    }
  }

  static boolean isPlayable(Scene scene) {
    return scene != null && notBlank(scene.id()) && notBlank(scene.persona())
        && notBlank(scene.character()) && notBlank(scene.context())
        && notEmpty(scene.openings()) && notEmpty(scene.rules()) && notEmpty(scene.examples())
        && notEmpty(scene.twists()) && scene.title() != null && notBlank(scene.title().get("en"))
        && scene.goal() != null && notBlank(scene.goal().get("en"));
  }

  private static boolean notBlank(String text) {
    return text != null && !text.isBlank();
  }

  private static boolean notEmpty(List<String> lines) {
    return lines != null && !lines.isEmpty() && lines.stream().allMatch(ScenarioCatalog::notBlank);
  }

  public List<Scene> scenes() {
    return scenes;
  }

  /** Changes whenever the file does, so the app can tell a stale copy from a current one. */
  public String version() {
    return version;
  }

  public Optional<Scene> find(String id) {
    if (id == null) {
      return Optional.empty();
    }
    return scenes.stream().filter(scene -> scene.id().equals(id)).findFirst();
  }
}
