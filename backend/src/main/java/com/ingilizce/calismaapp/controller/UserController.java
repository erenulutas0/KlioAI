package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.dto.UserDto;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.service.UserService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/users")
public class UserController {

    private final UserService userService;
    private final CurrentUserContext currentUserContext;

    public UserController(UserService userService, CurrentUserContext currentUserContext) {
        this.userService = userService;
        this.currentUserContext = currentUserContext;
    }

    private UserDto mapToUserDto(User user) {
        return new UserDto(user.getId(), user.getDisplayName(), user.getUserTag(), user.isOnline());
    }

    private Map<String, Object> mapToUserProfile(User user) {
        Map<String, Object> profile = new HashMap<>();
        profile.put("id", user.getId());
        profile.put("userId", user.getId());
        profile.put("email", user.getEmail());
        profile.put("displayName", user.getDisplayName());
        profile.put("userTag", user.getUserTag());
        profile.put("role", user.getRole().name());
        profile.put("subscriptionEndDate", user.getSubscriptionEndDate() != null ? user.getSubscriptionEndDate() : "null");
        profile.put("isSubscriptionActive", user.isSubscriptionActive());
        profile.put("aiPlanCode", user.getAiPlanCode());
        profile.put("trialEligible", user.isTrialEligible());
        profile.put("createdAt", user.getCreatedAt());
        profile.put("lastSeenAt", user.getLastSeenAt() != null ? user.getLastSeenAt() : "null");
        profile.put("emailVerified", user.isEmailVerified());
        profile.put("emailVerifiedAt", user.getEmailVerifiedAt() != null ? user.getEmailVerifiedAt() : "null");
        return profile;
    }

    @GetMapping
    public ResponseEntity<List<UserDto>> getAllUsers(
            @RequestHeader(value = "X-User-Id", required = false) String currentUserId) {
        List<User> users = userService.getAllUsers();

        if (currentUserId != null) {
            try {
                Long id = Long.parseLong(currentUserId);
                users = users.stream()
                        .filter(u -> !u.getId().equals(id))
                        .collect(Collectors.toList());
            } catch (NumberFormatException ignored) {
            }
        }

        // Online kullanıcıları önce göster
        List<UserDto> dtos = users.stream()
                .sorted(Comparator.comparing(User::isOnline).reversed()
                        .thenComparing(u -> u.getLastSeenAt() != null ? u.getLastSeenAt() : LocalDateTime.MIN,
                                Comparator.reverseOrder()))
                .map(this::mapToUserDto)
                .collect(Collectors.toList());

        return ResponseEntity.ok(dtos);
    }

    // Get current user details (simulated by ID)
    @GetMapping("/{id}")
    public ResponseEntity<Map<String, Object>> getUserProfile(@PathVariable Long id) {
        if (!currentUserContext.isSelfOrAdmin(id)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        Optional<User> user = userService.getUserById(id);
        return user.map(value -> ResponseEntity.ok(mapToUserProfile(value)))
                .orElse(ResponseEntity.notFound().build());
    }

    // Heartbeat endpoint - call this periodically to update online status
    @PostMapping("/heartbeat")
    public ResponseEntity<Map<String, Object>> heartbeat(
            @RequestHeader("X-User-Id") Long userId) {
        userService.updateLastSeen(userId);
        return ResponseEntity.ok(Map.of("status", "ok", "timestamp", LocalDateTime.now().toString()));
    }

    // Admin/Test endpoint to extend subscription
    @PostMapping("/{id}/subscription/extend")
    public ResponseEntity<Map<String, Object>> extendSubscription(@PathVariable Long id,
            @RequestBody Map<String, Integer> request) {
        if (currentUserContext.shouldEnforceAuthz() && !currentUserContext.hasRole("ADMIN")) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Admin role required"));
        }

        Integer days = request.get("days");
        if (days == null || days <= 0) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid days provided"));
        }

        boolean success = userService.extendSubscription(id, days);
        if (success) {
            Optional<User> updatedUser = userService.getUserById(id);
            return ResponseEntity.ok(Map.of(
                    "message", "Subscription extended successfully",
                    "newEndDate", updatedUser.get().getSubscriptionEndDate()));
        }
        return ResponseEntity.notFound().build();
    }

    @GetMapping("/{id}/subscription/status")
    public ResponseEntity<Map<String, Object>> getSubscriptionStatus(@PathVariable Long id) {
        if (!currentUserContext.isSelfOrAdmin(id)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        Optional<User> user = userService.getUserById(id);
        if (user.isPresent()) {
            return ResponseEntity.ok(Map.of(
                    "userId", id,
                    "isActive", user.get().isSubscriptionActive(),
                    "endDate",
                    user.get().getSubscriptionEndDate() != null ? user.get().getSubscriptionEndDate() : "null"));
        }
        return ResponseEntity.notFound().build();
    }
}

