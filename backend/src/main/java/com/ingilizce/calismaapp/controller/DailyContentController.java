package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.DailyExamPackService;
import com.ingilizce.calismaapp.service.DailyWordsService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.Map;

@RestController
@RequestMapping("/api/content")
public class DailyContentController {

    private final DailyWordsService dailyWordsService;
    private final DailyExamPackService dailyExamPackService;

    public DailyContentController(DailyWordsService dailyWordsService,
                                  DailyExamPackService dailyExamPackService) {
        this.dailyWordsService = dailyWordsService;
        this.dailyExamPackService = dailyExamPackService;
    }

    @GetMapping("/daily-words")
    public ResponseEntity<Map<String, Object>> getDailyWords() {
        var words = dailyWordsService.getDailyWords(LocalDate.now());
        return ResponseEntity.ok(Map.of(
                "success", true,
                "words", words
        ));
    }

    @GetMapping("/daily-exam-pack")
    public ResponseEntity<Map<String, Object>> getDailyExamPack(
            @RequestParam(name = "exam", required = false, defaultValue = "yds") String exam) {
        var payload = dailyExamPackService.getDailyExamPack(LocalDate.now(), exam);
        return ResponseEntity.ok(Map.of(
                "success", true,
                "data", payload
        ));
    }
}
