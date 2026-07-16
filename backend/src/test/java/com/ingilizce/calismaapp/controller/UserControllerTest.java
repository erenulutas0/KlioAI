package com.ingilizce.calismaapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.service.UserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.Mockito.never;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@DisplayName("User Controller Tests")
class UserControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private UserService userService;

    @Autowired
    private ObjectMapper objectMapper;

    private User userOne;
    private User userTwo;
    private User userThree;

    @BeforeEach
    void setUp() {
        userOne = new User("one@example.com", "hash", "One");
        userOne.setId(1L);
        userOne.setUserTag("#11111");
        userOne.setLastSeenAt(LocalDateTime.now().minusMinutes(1));

        userTwo = new User("two@example.com", "hash", "Two");
        userTwo.setId(2L);
        userTwo.setUserTag("#22222");
        userTwo.setLastSeenAt(LocalDateTime.now().minusMinutes(10));

        userThree = new User("three@example.com", "hash", "Three");
        userThree.setId(3L);
        userThree.setUserTag("#33333");
        userThree.setLastSeenAt(LocalDateTime.now().minusMinutes(2));
    }

    @Nested
    @DisplayName("GET /api/users")
    class GetUsersTests {

        @Test
        @DisplayName("Should sort online users first and exclude current user")
        void testGetAllUsersFilteredAndSorted() throws Exception {
            Mockito.when(userService.getAllUsers()).thenReturn(List.of(userTwo, userThree, userOne));

            mockMvc.perform(get("/api/users").header("X-User-Id", "1"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(2))
                    .andExpect(jsonPath("$[0].id").value(3))
                    .andExpect(jsonPath("$[0].online").value(true))
                    .andExpect(jsonPath("$[1].id").value(2))
                    .andExpect(jsonPath("$[1].online").value(false));
        }

        @Test
        @DisplayName("Should ignore invalid current user header")
        void testGetAllUsersInvalidHeader() throws Exception {
            Mockito.when(userService.getAllUsers()).thenReturn(List.of(userOne, userTwo, userThree));

            mockMvc.perform(get("/api/users").header("X-User-Id", "invalid"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.length()").value(3));
        }
    }

    @Nested
    @DisplayName("GET /api/users/{id}")
    class ProfileTests {

        @Test
        @DisplayName("Should return user profile when found")
        void testGetUserProfileFound() throws Exception {
            Mockito.when(userService.getUserById(1L)).thenReturn(Optional.of(userOne));

            mockMvc.perform(get("/api/users/1"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.email").value("one@example.com"));
        }

        @Test
        @DisplayName("Should return not found when user does not exist")
        void testGetUserProfileNotFound() throws Exception {
            Mockito.when(userService.getUserById(99L)).thenReturn(Optional.empty());

            mockMvc.perform(get("/api/users/99"))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("POST /api/users/heartbeat")
    class HeartbeatTests {

        @Test
        @DisplayName("Should update last seen for valid user id header")
        void testHeartbeatSuccess() throws Exception {
            mockMvc.perform(post("/api/users/heartbeat").header("X-User-Id", "1"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("ok"))
                    .andExpect(jsonPath("$.timestamp").exists());

            Mockito.verify(userService).updateLastSeen(1L);
        }

        @Test
        @DisplayName("Should return error for invalid user id header")
        void testHeartbeatInvalidHeader() throws Exception {
            mockMvc.perform(post("/api/users/heartbeat").header("X-User-Id", "abc"))
                    .andExpect(status().isBadRequest());

            Mockito.verify(userService, never()).updateLastSeen(Mockito.anyLong());
        }
    }

    @Nested
    @DisplayName("POST /api/users/{id}/subscription/extend")
    class ExtendSubscriptionTests {

        @Test
        @DisplayName("Should extend subscription when input is valid")
        void testExtendSubscriptionSuccess() throws Exception {
            userOne.setSubscriptionEndDate(LocalDateTime.now().plusDays(30));
            Mockito.when(userService.extendSubscription(1L, 30)).thenReturn(true);
            Mockito.when(userService.getUserById(1L)).thenReturn(Optional.of(userOne));

            mockMvc.perform(post("/api/users/1/subscription/extend")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(objectMapper.writeValueAsString(Map.of("days", 30))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.message").value("Subscription extended successfully"))
                    .andExpect(jsonPath("$.newEndDate").exists());
        }

        @Test
        @DisplayName("Should reject invalid days input")
        void testExtendSubscriptionInvalidDays() throws Exception {
            mockMvc.perform(post("/api/users/1/subscription/extend")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(objectMapper.writeValueAsString(Map.of("days", 0))))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Invalid days provided"));

            Mockito.verify(userService, never()).extendSubscription(Mockito.anyLong(), Mockito.anyInt());
        }

        @Test
        @DisplayName("Should return not found when extension target user does not exist")
        void testExtendSubscriptionNotFound() throws Exception {
            Mockito.when(userService.extendSubscription(42L, 15)).thenReturn(false);

            mockMvc.perform(post("/api/users/42/subscription/extend")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(objectMapper.writeValueAsString(Map.of("days", 15))))
                    .andExpect(status().isNotFound());
        }
    }

    @Nested
    @DisplayName("GET /api/users/{id}/subscription/status")
    class SubscriptionStatusTests {

        @Test
        @DisplayName("Should return active subscription status")
        void testGetSubscriptionStatusActive() throws Exception {
            userOne.setSubscriptionEndDate(LocalDateTime.now().plusDays(7));
            userOne.setAiPlanCode("PREMIUM");
            Mockito.when(userService.getUserById(1L)).thenReturn(Optional.of(userOne));

            mockMvc.perform(get("/api/users/1/subscription/status"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.userId").value(1))
                    .andExpect(jsonPath("$.isActive").value(true))
                    .andExpect(jsonPath("$.aiPlanCode").value("PREMIUM"))
                    .andExpect(jsonPath("$.endDate").exists());
        }

        @Test
        @DisplayName("Should return not found for missing user in subscription status")
        void testGetSubscriptionStatusNotFound() throws Exception {
            Mockito.when(userService.getUserById(999L)).thenReturn(Optional.empty());

            mockMvc.perform(get("/api/users/999/subscription/status"))
                    .andExpect(status().isNotFound());
        }
    }
}
