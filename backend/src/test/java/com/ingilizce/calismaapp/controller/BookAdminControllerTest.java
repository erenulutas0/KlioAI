package com.ingilizce.calismaapp.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ingilizce.calismaapp.security.CurrentUserContext;
import com.ingilizce.calismaapp.service.BookImportService;
import com.ingilizce.calismaapp.service.BookTranslationService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * The reading shelf's operator endpoints.
 *
 * <p>One of these spends money on every call. An endpoint that spends money is
 * an endpoint someone can run a bill up with, so what matters here is not that
 * it works but that it refuses — and that it refuses *before* asking the model
 * for anything.
 */
@SpringBootTest
@AutoConfigureMockMvc
class BookAdminControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private CurrentUserContext currentUserContext;

    @MockBean
    private BookTranslationService translationService;

    @MockBean
    private BookImportService importService;

    private void signedInAs(boolean admin) {
        when(currentUserContext.shouldEnforceAuthz()).thenReturn(true);
        when(currentUserContext.hasRole("ADMIN")).thenReturn(admin);
    }

    @Test
    @DisplayName("a learner cannot spend the project's money on translation")
    void translationIsAdminOnly() throws Exception {
        signedInAs(false);

        mockMvc.perform(post("/api/admin/books/peter-rabbit/translate"))
                .andExpect(status().isForbidden());

        // The refusal has to come first. Checking the role after calling the
        // model would still return 403 and still have paid for the answer.
        verify(translationService, never()).translateBook(anyLong(), anyString(), any(Integer.class), anyString());
    }

    @Test
    @DisplayName("a learner cannot rewrite what every reader sees")
    void importIsAdminOnly() throws Exception {
        signedInAs(false);

        mockMvc.perform(post("/api/admin/books/import"))
                .andExpect(status().isForbidden());

        verify(importService, never()).importBook(anyString(), anyString(), anyString(),
                anyString(), anyString(), anyString(), anyString());
    }

    @Test
    @DisplayName("the shelf listing is closed too")
    void statusIsAdminOnly() throws Exception {
        signedInAs(false);

        mockMvc.perform(get("/api/admin/books/status"))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("translating a book nobody imported is refused, not attempted")
    void refusesAnUnknownBook() throws Exception {
        signedInAs(true);

        mockMvc.perform(post("/api/admin/books/not-a-book/translate"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").exists());

        verify(translationService, never()).translateBook(anyLong(), anyString(), any(Integer.class), anyString());
    }

    @Test
    @DisplayName("importing a title that is not on the shelf is refused by name")
    void refusesAnUnshelvedSlug() throws Exception {
        signedInAs(true);

        mockMvc.perform(post("/api/admin/books/import").param("slug", "war-and-peace"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").exists());
    }
}
