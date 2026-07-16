package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.security.JwtAuthenticationFilter;
import com.ingilizce.calismaapp.security.UserHeaderConsistencyFilter;
import com.ingilizce.calismaapp.service.DevicePushTokenService;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = PushTokenController.class)
@AutoConfigureMockMvc(addFilters = false)
class PushTokenControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private DevicePushTokenService devicePushTokenService;

    @MockBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @MockBean
    private UserHeaderConsistencyFilter userHeaderConsistencyFilter;

    @Test
    void getPreferences_ShouldReturnCurrentPreferences() throws Exception {
        when(devicePushTokenService.getPreferences(4L))
                .thenReturn(Map.of(
                        "dailyRemindersEnabled", true,
                        "streakGuardEnabled", false,
                        "subscriptionAlertsEnabled", true));

        mockMvc.perform(get("/api/push-tokens/preferences")
                        .header("X-User-Id", "4"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.dailyRemindersEnabled").value(true))
                .andExpect(jsonPath("$.streakGuardEnabled").value(false))
                .andExpect(jsonPath("$.subscriptionAlertsEnabled").value(true));

        verify(devicePushTokenService).getPreferences(4L);
    }

    @Test
    void updatePreferences_ShouldForwardPayload() throws Exception {
        when(devicePushTokenService.updatePreferences(eq(4L), org.mockito.ArgumentMatchers.anyMap()))
                .thenReturn(Map.of(
                        "dailyRemindersEnabled", true,
                        "streakGuardEnabled", true,
                        "productUpdatesEnabled", false));

        mockMvc.perform(put("/api/push-tokens/preferences")
                        .header("X-User-Id", "4")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dailyRemindersEnabled\":true,\"streakGuardEnabled\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.dailyRemindersEnabled").value(true))
                .andExpect(jsonPath("$.streakGuardEnabled").value(true));

        verify(devicePushTokenService).updatePreferences(eq(4L), org.mockito.ArgumentMatchers.anyMap());
    }
}
