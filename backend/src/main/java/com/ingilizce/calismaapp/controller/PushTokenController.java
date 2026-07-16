package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.DevicePushTokenService;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/push-tokens")
public class PushTokenController {

    private final DevicePushTokenService devicePushTokenService;

    public PushTokenController(DevicePushTokenService devicePushTokenService) {
        this.devicePushTokenService = devicePushTokenService;
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> registerToken(
            @RequestHeader("X-User-Id") Long userId,
            @RequestBody Map<String, String> payload) {
        try {
            return ResponseEntity.ok(devicePushTokenService.registerToken(userId, payload));
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(Map.of("error", ex.getMessage()));
        }
    }

    @GetMapping("/preferences")
    public ResponseEntity<Map<String, Object>> getPreferences(
            @RequestHeader("X-User-Id") Long userId) {
        try {
            return ResponseEntity.ok(devicePushTokenService.getPreferences(userId));
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(Map.of("error", ex.getMessage()));
        }
    }

    @PutMapping("/preferences")
    public ResponseEntity<Map<String, Object>> updatePreferences(
            @RequestHeader("X-User-Id") Long userId,
            @RequestBody Map<String, Object> payload) {
        try {
            return ResponseEntity.ok(devicePushTokenService.updatePreferences(userId, payload));
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(Map.of("error", ex.getMessage()));
        }
    }

    @DeleteMapping
    public ResponseEntity<Map<String, Object>> disableToken(
            @RequestHeader("X-User-Id") Long userId,
            @RequestBody Map<String, String> payload) {
        try {
            if (payload == null) {
                return ResponseEntity.badRequest().body(Map.of("error", "Missing push token payload"));
            }
            return ResponseEntity.ok(devicePushTokenService.disableToken(userId, payload.get("token")));
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(Map.of("error", ex.getMessage()));
        }
    }
}
