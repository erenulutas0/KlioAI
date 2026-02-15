package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.model.Achievement;
import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.service.ProgressService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Map;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:progressdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class ProgressControllerTest {

    private static final String USER_ID_HEADER = "X-User-Id";
    private static final Long USER_ID = 1L;

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private ProgressService progressService;

    @MockBean
    private CurrentUserContext currentUserContext;

    @BeforeEach
    void setUp() {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(false);
    }

    @Test
    void getStatsReturnsOk() throws Exception {
        when(progressService.getStats(USER_ID)).thenReturn(Map.of("level", 3, "totalXp", 240));

        mockMvc.perform(get("/api/progress/stats").header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.level").value(3))
                .andExpect(jsonPath("$.totalXp").value(240));
    }

    @Test
    void getStatsReturnsInternalServerErrorWhenServiceFails() throws Exception {
        when(progressService.getStats(USER_ID)).thenThrow(new RuntimeException("failure"));

        mockMvc.perform(get("/api/progress/stats").header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void getAllAchievementsReturnsOk() throws Exception {
        when(progressService.getAllAchievements(USER_ID)).thenReturn(List.of(Map.of("code", "FIRST_WORD")));

        mockMvc.perform(get("/api/progress/achievements").header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].code").value("FIRST_WORD"));
    }

    @Test
    void getAllAchievementsReturnsInternalServerErrorWhenServiceFails() throws Exception {
        when(progressService.getAllAchievements(USER_ID)).thenThrow(new RuntimeException("failure"));

        mockMvc.perform(get("/api/progress/achievements").header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void getUnlockedAchievementsReturnsOk() throws Exception {
        when(progressService.getUnlockedAchievements(USER_ID)).thenReturn(List.of(Map.of("code", "STREAK_3")));

        mockMvc.perform(get("/api/progress/achievements/unlocked").header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].code").value("STREAK_3"));
    }

    @Test
    void getUnlockedAchievementsReturnsInternalServerErrorWhenServiceFails() throws Exception {
        when(progressService.getUnlockedAchievements(USER_ID)).thenThrow(new RuntimeException("failure"));

        mockMvc.perform(get("/api/progress/achievements/unlocked").header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void checkAchievementsReturnsOk() throws Exception {
        when(progressService.checkAndUnlockAchievements(USER_ID)).thenReturn(List.of(Achievement.FIRST_WORD));

        mockMvc.perform(post("/api/progress/check-achievements").header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0]").value("FIRST_WORD"));
    }

    @Test
    void checkAchievementsReturnsInternalServerErrorWhenServiceFails() throws Exception {
        when(progressService.checkAndUnlockAchievements(USER_ID)).thenThrow(new RuntimeException("failure"));

        mockMvc.perform(post("/api/progress/check-achievements").header(USER_ID_HEADER, USER_ID))
                .andExpect(status().isInternalServerError());
    }

    @Test
    void awardXpReturnsUpdatedStats() throws Exception {
        when(progressService.getStats(USER_ID)).thenReturn(Map.of("totalXp", 300));

        mockMvc.perform(post("/api/progress/award-xp")
                .header(USER_ID_HEADER, USER_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"xp\":25,\"reason\":\"daily\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.totalXp").value(300));

        verify(progressService).awardXp(USER_ID, 25, "daily");
    }

    @Test
    void awardXpReturnsBadRequestWhenInputIsInvalid() throws Exception {
        mockMvc.perform(post("/api/progress/award-xp")
                .header(USER_ID_HEADER, USER_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"reason\":\"missing-xp\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void awardXpReturnsForbiddenWhenAuthzEnforcedAndNotAdmin() throws Exception {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(true);
        when(currentUserContext.hasRole("ADMIN")).thenReturn(false);

        mockMvc.perform(post("/api/progress/award-xp")
                .header(USER_ID_HEADER, USER_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"xp\":25,\"reason\":\"daily\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("Admin role required"));
    }

    @Test
    void endpointsReturnBadRequestWhenUserHeaderMissing() throws Exception {
        mockMvc.perform(get("/api/progress/stats"))
                .andExpect(status().isBadRequest());
    }
}
