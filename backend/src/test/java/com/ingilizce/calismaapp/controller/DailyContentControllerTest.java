package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.DailyExamPackService;
import com.ingilizce.calismaapp.service.DailyWordsService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
public class DailyContentControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private DailyWordsService dailyWordsService;

    @MockBean
    private DailyExamPackService dailyExamPackService;

    @Test
    void dailyWordsReturnsOkWithWordsArray() throws Exception {
        when(dailyWordsService.getDailyWords(LocalDate.now()))
                .thenReturn(List.of(
                        Map.of("id", 1, "word", "resilient"),
                        Map.of("id", 2, "word", "insight")
                ));

        mockMvc.perform(get("/api/content/daily-words")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.words").isArray())
                .andExpect(jsonPath("$.words[0].word").value("resilient"));
    }

    @Test
    void dailyExamPackReturnsOkWithDataObject() throws Exception {
        when(dailyExamPackService.getDailyExamPack(LocalDate.now(), "yds"))
                .thenReturn(Map.of("exam", "yds", "date", LocalDate.now().toString(), "topics", List.of()));

        mockMvc.perform(get("/api/content/daily-exam-pack?exam=yds")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.exam").value("yds"))
                .andExpect(jsonPath("$.data.topics").isArray());
    }
}
