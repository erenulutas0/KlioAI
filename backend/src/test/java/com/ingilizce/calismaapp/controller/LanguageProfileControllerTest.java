package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.LanguageProfile;
import com.ingilizce.calismaapp.service.LanguageProfileService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.NoSuchElementException;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "GROQ_API_KEY=dummy-key",
        "spring.datasource.url=jdbc:h2:mem:langprofiledb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class LanguageProfileControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private LanguageProfileService languageProfileService;

    private static LanguageProfile profile(Long id, String target, boolean active) {
        LanguageProfile profile = new LanguageProfile(1L, "Turkish", target, "B1", "Speaking", active);
        profile.setId(id);
        profile.setCreatedAt(LocalDateTime.of(2026, 8, 1, 9, 0));
        return profile;
    }

    @Test
    void list_ReturnsTheDocumentedShape_AndEnsuresADefaultExists() throws Exception {
        when(languageProfileService.listProfiles(1L))
                .thenReturn(List.of(profile(5L, "English", true), profile(6L, "German", false)));

        mockMvc.perform(get("/api/language-profiles").header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].id").value(5))
                .andExpect(jsonPath("$[0].sourceLanguage").value("Turkish"))
                .andExpect(jsonPath("$[0].targetLanguage").value("English"))
                .andExpect(jsonPath("$[0].level").value("B1"))
                .andExpect(jsonPath("$[0].learningGoal").value("Speaking"))
                .andExpect(jsonPath("$[0].isActive").value(true))
                .andExpect(jsonPath("$[0].createdAt").exists())
                .andExpect(jsonPath("$[1].isActive").value(false));

        verify(languageProfileService).ensureDefaultProfile(1L);
    }

    @Test
    void list_WithoutHeader_IsBadRequest() throws Exception {
        mockMvc.perform(get("/api/language-profiles")).andExpect(status().isBadRequest());
        verify(languageProfileService, never()).listProfiles(anyLong());
    }

    @Test
    void create_Returns201WithTheProfile() throws Exception {
        when(languageProfileService.createProfile(1L, "Turkish", "German", "A2", "Travel"))
                .thenReturn(profile(8L, "German", false));

        mockMvc.perform(post("/api/language-profiles")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"sourceLanguage":"Turkish","targetLanguage":"German","level":"A2","learningGoal":"Travel"}
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(8))
                .andExpect(jsonPath("$.targetLanguage").value("German"));
    }

    @Test
    void create_DuplicateTarget_Is409WithAMessage() throws Exception {
        when(languageProfileService.createProfile(eq(1L), any(), any(), any(), any()))
                .thenThrow(new LanguageProfileService.DuplicateTargetLanguageException("English"));

        mockMvc.perform(post("/api/language-profiles")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sourceLanguage\":\"Turkish\",\"targetLanguage\":\"English\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("A profile for English already exists"));
    }

    @Test
    void create_InvalidInput_Is400() throws Exception {
        when(languageProfileService.createProfile(eq(1L), any(), any(), any(), any()))
                .thenThrow(new IllegalArgumentException("targetLanguage is required"));

        mockMvc.perform(post("/api/language-profiles")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sourceLanguage\":\"Turkish\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void update_Returns200_Or404ForAnotherUsersProfile() throws Exception {
        when(languageProfileService.updateProfile(1L, 5L, "C1", null)).thenReturn(profile(5L, "English", true));
        when(languageProfileService.updateProfile(1L, 99L, "C1", null))
                .thenThrow(new NoSuchElementException("Language profile not found: 99"));

        mockMvc.perform(put("/api/language-profiles/5")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"level\":\"C1\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(5));

        mockMvc.perform(put("/api/language-profiles/99")
                        .header("X-User-Id", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"level\":\"C1\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void activate_ReturnsTheNowActiveProfile_Or404() throws Exception {
        when(languageProfileService.activate(1L, 6L)).thenReturn(profile(6L, "German", true));
        when(languageProfileService.activate(1L, 99L))
                .thenThrow(new NoSuchElementException("Language profile not found: 99"));

        mockMvc.perform(post("/api/language-profiles/6/activate").header("X-User-Id", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(6))
                .andExpect(jsonPath("$.isActive").value(true));

        mockMvc.perform(post("/api/language-profiles/99/activate").header("X-User-Id", "1"))
                .andExpect(status().isNotFound());
    }
}
