package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class GroqService {

    private static final Logger logger = LoggerFactory.getLogger(GroqService.class);

    public record ChatCompletionResult(String content, int promptTokens, int completionTokens, int totalTokens) {
        public static ChatCompletionResult of(String content, int promptTokens, int completionTokens, int totalTokens) {
            return new ChatCompletionResult(content, promptTokens, completionTokens, totalTokens);
        }

        public static ChatCompletionResult empty() {
            return new ChatCompletionResult(null, 0, 0, 0);
        }
    }

    @Value("${groq.api.key}")
    private String apiKey;

    @Value("${groq.api.url}")
    private String apiUrl;

    @Value("${groq.api.model}")
    private String model;

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;
    private final AtomicInteger consecutiveFailures = new AtomicInteger(0);
    private volatile long circuitOpenUntilMs = 0L;

    @Value("${groq.resilience.max-attempts:3}")
    private int maxAttempts;

    @Value("${groq.resilience.initial-backoff-ms:250}")
    private long initialBackoffMs;

    @Value("${groq.resilience.max-backoff-ms:2000}")
    private long maxBackoffMs;

    @Value("${groq.resilience.call-timeout-budget-ms:35000}")
    private long callTimeoutBudgetMs;

    @Value("${groq.resilience.failure-threshold:5}")
    private int failureThreshold;

    @Value("${groq.resilience.open-duration-ms:30000}")
    private long openDurationMs;

    public GroqService(@Value("${app.security.allow-insecure-ssl:false}") boolean allowInsecureSsl) {
        this.objectMapper = new ObjectMapper();
        this.restTemplate = createRestTemplate(allowInsecureSsl);
        if (allowInsecureSsl) {
            logger.warn("GroqService initialized with INSECURE SSL mode (local-dev only)");
        } else {
            logger.info("GroqService initialized with strict SSL verification");
        }
    }

    protected RestTemplate createRestTemplate(boolean allowInsecureSsl) {
        if (!allowInsecureSsl) {
            return createSecureRestTemplate();
        }

        try {
            TrustManager[] trustAllCerts = createTrustAllManagers();
            SSLContext sslContext = createSslContext("TLS");
            initializeSslContext(sslContext, trustAllCerts);
            SimpleClientHttpRequestFactory factory = createInsecureRequestFactory(sslContext);
            return new RestTemplate(factory);
        } catch (Exception e) {
            logger.error("Failed to create insecure RestTemplate, falling back to strict SSL", e);
            return createSecureRestTemplate();
        }
    }

    protected RestTemplate createSecureRestTemplate() {
        SimpleClientHttpRequestFactory secureFactory = new SimpleClientHttpRequestFactory();
        secureFactory.setConnectTimeout(60000);
        secureFactory.setReadTimeout(60000);
        return new RestTemplate(secureFactory);
    }

    protected TrustManager[] createTrustAllManagers() {
        return new TrustManager[] {
                new X509TrustManager() {
                    @Override
                    public java.security.cert.X509Certificate[] getAcceptedIssuers() {
                        return null;
                    }

                    @Override
                    public void checkClientTrusted(java.security.cert.X509Certificate[] certs, String authType) {
                    }

                    @Override
                    public void checkServerTrusted(java.security.cert.X509Certificate[] certs, String authType) {
                    }
                }
        };
    }

    protected SSLContext createSslContext(String protocol) throws Exception {
        return SSLContext.getInstance(protocol);
    }

    protected void initializeSslContext(SSLContext sslContext, TrustManager[] trustManagers) throws Exception {
        sslContext.init(null, trustManagers, new java.security.SecureRandom());
    }

    protected SimpleClientHttpRequestFactory createInsecureRequestFactory(SSLContext sslContext) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory() {
            @Override
            protected java.net.HttpURLConnection openConnection(java.net.URL url, java.net.Proxy proxy)
                    throws java.io.IOException {
                java.net.HttpURLConnection connection = super.openConnection(url, proxy);
                if (connection instanceof javax.net.ssl.HttpsURLConnection) {
                    ((javax.net.ssl.HttpsURLConnection) connection).setSSLSocketFactory(sslContext.getSocketFactory());
                    ((javax.net.ssl.HttpsURLConnection) connection).setHostnameVerifier((hostname, session) -> true);
                }
                return connection;
            }
        };
        factory.setConnectTimeout(60000);
        factory.setReadTimeout(60000);
        return factory;
    }

    /**
     * Send a completion request to Groq API
     * 
     * @param messages     List of messages (role, content)
     * @param jsonResponse If true, enforces JSON object response format
     * @return Content string from the response
     */
    public String chatCompletion(List<Map<String, String>> messages, boolean jsonResponse) {
        ChatCompletionResult result = chatCompletionWithUsage(messages, jsonResponse, null, null, null);
        return result != null ? result.content() : null;
    }

    public String chatCompletion(List<Map<String, String>> messages,
                                 boolean jsonResponse,
                                 String modelOverride) {
        ChatCompletionResult result = chatCompletionWithUsage(messages, jsonResponse, null, null, modelOverride);
        return result != null ? result.content() : null;
    }

    /**
     * Send a completion request to Groq API and return both content and token usage.
     *
     * @param messages     List of messages (role, content)
     * @param jsonResponse If true, enforces JSON object response format
     * @param maxTokens    Optional max tokens for completion
     * @param temperature  Optional temperature override
     * @return Result including content and token usage (prompt/completion/total). Missing usage is returned as zeros.
     */
    public ChatCompletionResult chatCompletionWithUsage(List<Map<String, String>> messages,
                                                       boolean jsonResponse,
                                                       Integer maxTokens,
                                                       Double temperature) {
        return chatCompletionWithUsage(messages, jsonResponse, maxTokens, temperature, null);
    }

    public ChatCompletionResult chatCompletionWithUsage(List<Map<String, String>> messages,
                                                        boolean jsonResponse,
                                                        Integer maxTokens,
                                                        Double temperature,
                                                        String modelOverride) {
        String selectedModel = (modelOverride != null && !modelOverride.isBlank()) ? modelOverride.trim() : model;
        logger.info("Groq Request - Model: {}, URL: {}, Key present: {}", selectedModel, apiUrl,
                (apiKey != null && !apiKey.isEmpty()));

        if (isCircuitOpen()) {
            throw new RuntimeException("Groq API Error: circuit is open");
        }

        long deadlineMs = System.currentTimeMillis() + Math.max(1L, callTimeoutBudgetMs);
        int attempts = Math.max(1, maxAttempts);
        long baseBackoffMs = Math.max(0L, initialBackoffMs);
        long backoffCapMs = Math.max(baseBackoffMs, maxBackoffMs);
        RuntimeException lastRetryableFailure = null;

        for (int attempt = 1; attempt <= attempts; attempt++) {
            try {
                ChatCompletionResult completion = executeChatCompletionWithJsonFallback(
                        messages,
                        jsonResponse,
                        maxTokens,
                        temperature,
                        selectedModel);
                recordSuccess();
                return completion;
            } catch (NonRetryableGroqException e) {
                recordFailure();
                throw e;
            } catch (RetryableGroqException e) {
                lastRetryableFailure = e;
                if (attempt == attempts) {
                    break;
                }

                long backoffMs = computeBackoffMs(attempt, baseBackoffMs, backoffCapMs);
                if ((System.currentTimeMillis() + backoffMs) >= deadlineMs) {
                    break;
                }

                logger.warn("Groq transient failure (attempt {}/{}). Retrying in {} ms", attempt, attempts, backoffMs);
                sleepQuietly(backoffMs);
            }
        }

        recordFailure();
        if (lastRetryableFailure != null) {
            throw lastRetryableFailure;
        }
        throw new RuntimeException("Groq API Error: retry budget exhausted");
    }

    private ChatCompletionResult executeChatCompletion(List<Map<String, String>> messages,
                                                      boolean jsonResponse,
                                                      Integer maxTokens,
                                                      Double temperature,
                                                      String selectedModel) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Authorization", "Bearer " + apiKey);

            Map<String, Object> requestBody = new HashMap<>();
            requestBody.put("model", selectedModel);
            requestBody.put("messages", messages);
            // Pratik modunda cümle üretirken çeşitlilik için temperature yüksek olmalı
            // JSON formatı genelde bozulmaz, gerekirse 0.6-0.8 arası iyidir
            requestBody.put("temperature", temperature != null ? temperature : 0.7);
            if (maxTokens != null && maxTokens > 0) {
                requestBody.put("max_tokens", maxTokens);
            }

            if (jsonResponse) {
                Map<String, String> responseFormat = new HashMap<>();
                responseFormat.put("type", "json_object");
                requestBody.put("response_format", responseFormat);
            }

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);

            logger.info("Sending request to Groq...");
            ResponseEntity<Map> response = restTemplate.postForEntity(apiUrl, entity, Map.class);
            logger.info("Groq Response Status: {}", response.getStatusCode());

            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                Map body = response.getBody();
                List choices = (List) body.get("choices");
                if (choices != null && !choices.isEmpty()) {
                    Map choice = (Map) choices.get(0);
                    Map message = (Map) choice.get("message");
                    String content = (String) message.get("content");

                    int promptTokens = 0;
                    int completionTokens = 0;
                    int totalTokens = 0;
                    Object usageObj = body.get("usage");
                    if (usageObj instanceof Map usage) {
                        Object pt = usage.get("prompt_tokens");
                        Object ct = usage.get("completion_tokens");
                        Object tt = usage.get("total_tokens");
                        if (pt instanceof Number n) promptTokens = n.intValue();
                        if (ct instanceof Number n) completionTokens = n.intValue();
                        if (tt instanceof Number n) totalTokens = n.intValue();
                    }

                    return ChatCompletionResult.of(content, promptTokens, completionTokens, totalTokens);
                }
            }
        } catch (HttpClientErrorException e) {
            String responseBody = e.getResponseBodyAsString();
            int statusCode = e.getStatusCode().value();
            logger.error("Groq API client error: Status={}, Body={}", e.getStatusCode(), responseBody);
            throw new NonRetryableGroqException(
                    "Groq API Error: " + responseBody,
                    statusCode,
                    responseBody,
                    e);
        } catch (HttpServerErrorException e) {
            logger.error("Groq API server error: Status={}, Body={}", e.getStatusCode(), e.getResponseBodyAsString());
            throw new RetryableGroqException("Groq API Error: " + e.getResponseBodyAsString(), e);
        } catch (ResourceAccessException e) {
            logger.error("Groq API transient access error", e);
            throw new RetryableGroqException("Failed to communicate with AI service: " + e.getMessage(), e);
        } catch (Exception e) {
            logger.error("Error calling Groq API", e);
            throw new RetryableGroqException("Failed to communicate with AI service: " + e.getMessage(), e);
        }
        return ChatCompletionResult.empty();
    }

    private ChatCompletionResult executeChatCompletionWithJsonFallback(List<Map<String, String>> messages,
                                                                       boolean jsonResponse,
                                                                       Integer maxTokens,
                                                                       Double temperature,
                                                                       String selectedModel) {
        try {
            ChatCompletionResult primary = executeChatCompletion(messages, jsonResponse, maxTokens, temperature, selectedModel);
            if (jsonResponse && isBlank(primary.content())) {
                ChatCompletionResult fallback = attemptJsonModeFallback(messages, maxTokens, temperature, selectedModel,
                        "empty response content");
                if (fallback != null && !isBlank(fallback.content())) {
                    return fallback;
                }
            }
            return primary;
        } catch (NonRetryableGroqException e) {
            if (shouldRetryWithoutResponseFormat(jsonResponse, e)) {
                try {
                    ChatCompletionResult fallback = attemptJsonModeFallback(messages, maxTokens, temperature, selectedModel,
                            "json response_format validation");
                    if (fallback != null) {
                        return fallback;
                    }
                } catch (RetryableGroqException retryable) {
                    throw retryable;
                } catch (NonRetryableGroqException fallbackFailure) {
                    logger.warn("Groq JSON fallback failed (model={}): {}", selectedModel, fallbackFailure.getMessage());
                }
            }
            throw e;
        }
    }

    private ChatCompletionResult attemptJsonModeFallback(List<Map<String, String>> messages,
                                                         Integer maxTokens,
                                                         Double temperature,
                                                         String selectedModel,
                                                         String reason) {
        logger.warn("Groq JSON-mode issue detected ({}). Retrying once without response_format. model={}",
                reason, selectedModel);
        List<Map<String, String>> fallbackMessages = withJsonOutputHint(messages);
        return executeChatCompletion(fallbackMessages, false, maxTokens, temperature, selectedModel);
    }

    private boolean shouldRetryWithoutResponseFormat(boolean jsonResponse, NonRetryableGroqException error) {
        if (!jsonResponse || error == null || error.statusCode() == null) {
            return false;
        }

        int statusCode = error.statusCode();
        if (statusCode != 400 && statusCode != 422) {
            return false;
        }

        String body = error.responseBody() != null
                ? error.responseBody().toLowerCase(Locale.ROOT)
                : "";

        return body.contains("json_validate_failed")
                || body.contains("response_format")
                || body.contains("failed_generation")
                || body.contains("schema");
    }

    private List<Map<String, String>> withJsonOutputHint(List<Map<String, String>> messages) {
        List<Map<String, String>> copied = new ArrayList<>();
        if (messages != null) {
            for (Map<String, String> message : messages) {
                copied.add(message != null ? new HashMap<>(message) : new HashMap<>());
            }
        }

        String hint = "IMPORTANT: Return ONLY valid JSON. No markdown, no explanations.";
        for (int i = copied.size() - 1; i >= 0; i--) {
            Map<String, String> msg = copied.get(i);
            String role = msg.get("role");
            if (role != null && "user".equalsIgnoreCase(role)) {
                String content = msg.getOrDefault("content", "");
                if (!content.toLowerCase(Locale.ROOT).contains("return only valid json")) {
                    msg.put("content", content + "\n\n" + hint);
                }
                return copied;
            }
        }

        copied.add(new HashMap<>(Map.of("role", "user", "content", hint)));
        return copied;
    }

    private boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private long computeBackoffMs(int attempt, long baseBackoffMs, long backoffCapMs) {
        if (baseBackoffMs <= 0L) {
            return 0L;
        }
        long backoff = baseBackoffMs * (1L << Math.max(0, attempt - 1));
        return Math.min(backoff, backoffCapMs);
    }

    private boolean isCircuitOpen() {
        return System.currentTimeMillis() < circuitOpenUntilMs;
    }

    private void recordSuccess() {
        consecutiveFailures.set(0);
        circuitOpenUntilMs = 0L;
    }

    private void recordFailure() {
        int failures = consecutiveFailures.incrementAndGet();
        if (failures >= Math.max(1, failureThreshold)) {
            circuitOpenUntilMs = System.currentTimeMillis() + Math.max(1000L, openDurationMs);
            logger.warn("Groq circuit opened for {} ms after {} consecutive failures",
                    Math.max(1000L, openDurationMs), failures);
            consecutiveFailures.set(0);
        }
    }

    protected void sleepQuietly(long ms) {
        if (ms <= 0) {
            return;
        }
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static class RetryableGroqException extends RuntimeException {
        RetryableGroqException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    private static class NonRetryableGroqException extends RuntimeException {
        NonRetryableGroqException(String message, Throwable cause) {
            this(message, null, null, cause);
        }

        NonRetryableGroqException(String message, Integer statusCode, String responseBody, Throwable cause) {
            super(message, cause);
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        private final Integer statusCode;
        private final String responseBody;

        Integer statusCode() {
            return statusCode;
        }

        String responseBody() {
            return responseBody;
        }
    }
}
