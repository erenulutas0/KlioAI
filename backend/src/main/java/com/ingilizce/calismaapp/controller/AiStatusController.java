package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.service.AiProbeSnapshot;
import com.ingilizce.calismaapp.service.SyntheticProbeService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Whether the AI provider is answering, in a form an uptime monitor can read.
 *
 * <p>Deliberately not a Spring {@code HealthIndicator}. A new indicator joins
 * the aggregate behind {@code /actuator/health}, which is what the container's
 * own healthcheck polls — a Groq outage would have marked the container
 * unhealthy and had Docker restart a backend that was working perfectly.
 *
 * <p>Deliberately not a Prometheus alert either. Those exist, and there are
 * twenty-two of them, and not one could ever have fired: the monitoring stack
 * was never deployed to the server, and its Alertmanager points at an
 * {@code http-https-echo} container that would have written each alert to its
 * own stdout. This endpoint is the shortest path from "the AI broke" to a
 * notification someone actually receives.
 *
 * <p>Public, like {@code /actuator/health}, so a free uptime service can poll
 * it. It exposes one word and a timestamp: no counts, no model names, no
 * provider errors.
 */
@RestController
@RequestMapping("/api/ops")
public class AiStatusController {

    private final SyntheticProbeService syntheticProbeService;

    public AiStatusController(SyntheticProbeService syntheticProbeService) {
        this.syntheticProbeService = syntheticProbeService;
    }

    /**
     * 200 while there is no reason to worry, 503 when there is.
     *
     * <p>An uptime monitor reads the status code and nothing else, so the
     * mapping is the whole contract: DOWN and STALE alert, UP and UNKNOWN do
     * not. UNKNOWN covers the minutes after a restart before the first probe
     * fires, which must never page anyone.
     */
    @GetMapping("/ai-status")
    public ResponseEntity<Map<String, Object>> aiStatus() {
        AiProbeSnapshot snapshot = syntheticProbeService.snapshot();

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", snapshot.health().name());
        body.put("lastProbeAt", snapshot.lastProbeAt() != null
                ? snapshot.lastProbeAt().toString()
                : null);

        return ResponseEntity
                .status(snapshot.isAlerting() ? HttpStatus.SERVICE_UNAVAILABLE : HttpStatus.OK)
                .body(body);
    }
}
