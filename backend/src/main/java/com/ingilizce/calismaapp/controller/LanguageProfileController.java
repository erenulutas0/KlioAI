package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.LanguageProfile;
import com.ingilizce.calismaapp.service.LanguageProfileService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

/**
 * Language profiles (V028). Scoped by {@code X-User-Id} like the rest of the API; a profile
 * id that belongs to another user is a 404, not a 403, so the response does not confirm the
 * id exists.
 */
@RestController
@RequestMapping("/api/language-profiles")
public class LanguageProfileController {

    private final LanguageProfileService languageProfileService;

    public LanguageProfileController(LanguageProfileService languageProfileService) {
        this.languageProfileService = languageProfileService;
    }

    @GetMapping
    public List<LanguageProfile> listProfiles(@RequestHeader("X-User-Id") Long userId) {
        // A user with no rows gets the default profile created here, so the list is never
        // empty and the client always has something to mark as active.
        languageProfileService.ensureDefaultProfile(userId);
        return languageProfileService.listProfiles(userId);
    }

    @PostMapping
    public ResponseEntity<?> createProfile(@RequestHeader("X-User-Id") Long userId,
            @RequestBody Map<String, String> payload) {
        try {
            LanguageProfile created = languageProfileService.createProfile(
                    userId,
                    payload.get("sourceLanguage"),
                    payload.get("targetLanguage"),
                    payload.get("level"),
                    payload.get("learningGoal"));
            return ResponseEntity.status(HttpStatus.CREATED).body(created);
        } catch (LanguageProfileService.DuplicateTargetLanguageException ex) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", ex.getMessage()));
        }
    }

    @PutMapping("/{id}")
    public ResponseEntity<LanguageProfile> updateProfile(@PathVariable Long id,
            @RequestHeader("X-User-Id") Long userId,
            @RequestBody Map<String, String> payload) {
        try {
            return ResponseEntity.ok(languageProfileService.updateProfile(
                    userId, id, payload.get("level"), payload.get("learningGoal")));
        } catch (NoSuchElementException ex) {
            return ResponseEntity.notFound().build();
        }
    }

    @PostMapping("/{id}/activate")
    public ResponseEntity<LanguageProfile> activateProfile(@PathVariable Long id,
            @RequestHeader("X-User-Id") Long userId) {
        try {
            return ResponseEntity.ok(languageProfileService.activate(userId, id));
        } catch (NoSuchElementException ex) {
            return ResponseEntity.notFound().build();
        }
    }
}
