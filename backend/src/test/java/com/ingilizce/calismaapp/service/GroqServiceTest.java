package com.ingilizce.calismaapp.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.ClientHttpRequest;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.RestTemplate;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class GroqServiceTest {

    @Mock
    private RestTemplate restTemplate;

    private GroqService groqService;

    @BeforeEach
    void setUp() {
        groqService = new GroqService(false);
        ReflectionTestUtils.setField(groqService, "apiKey", "test-api-key");
        ReflectionTestUtils.setField(groqService, "apiUrl", "http://api.groq.com/test");
        ReflectionTestUtils.setField(groqService, "model", "llama3-8b");
        ReflectionTestUtils.setField(groqService, "maxAttempts", 3);
        ReflectionTestUtils.setField(groqService, "initialBackoffMs", 0L);
        ReflectionTestUtils.setField(groqService, "maxBackoffMs", 0L);
        ReflectionTestUtils.setField(groqService, "callTimeoutBudgetMs", 10000L);
        ReflectionTestUtils.setField(groqService, "failureThreshold", 5);
        ReflectionTestUtils.setField(groqService, "openDurationMs", 30000L);
        ReflectionTestUtils.setField(groqService, "restTemplate", restTemplate);
    }

    @Test
    void chatCompletion_ShouldReturnContent_WhenResponseIsSuccessful() {
        // Prepare Mock Response
        Map<String, Object> messageMap = new HashMap<>();
        messageMap.put("content", "Hello AI");

        Map<String, Object> choiceMap = new HashMap<>();
        choiceMap.put("message", messageMap);

        List<Map<String, Object>> choices = new ArrayList<>();
        choices.add(choiceMap);

        Map<String, Object> bodyMap = new HashMap<>();
        bodyMap.put("choices", choices);

        ResponseEntity<Map> responseEntity = new ResponseEntity<>(bodyMap, HttpStatus.OK);

        when(restTemplate.postForEntity(eq("http://api.groq.com/test"), any(HttpEntity.class), eq(Map.class)))
                .thenReturn(responseEntity);

        // Call method
        List<Map<String, String>> messages = new ArrayList<>();
        Map<String, String> userMsg = new HashMap<>();
        userMsg.put("role", "user");
        userMsg.put("content", "Hi");
        messages.add(userMsg);

        String result = groqService.chatCompletion(messages, false);

        assertEquals("Hello AI", result);
        verify(restTemplate).postForEntity(eq("http://api.groq.com/test"), any(HttpEntity.class), eq(Map.class));
    }

    @Test
    void chatCompletion_ShouldThrowException_WhenApiFails() {
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class)))
                .thenThrow(new RuntimeException("Connection Refused"));

        List<Map<String, String>> messages = new ArrayList<>();

        Exception ignored = assertThrows(RuntimeException.class, () -> groqService.chatCompletion(messages, false));
    }

    @Test
    void chatCompletion_ShouldReturnNull_WhenResponseBodyIsNull() {
        ResponseEntity<Map> responseEntity = new ResponseEntity<>(null, HttpStatus.OK);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class))).thenReturn(responseEntity);

        String result = groqService.chatCompletion(new ArrayList<>(), false);

        assertNull(result);
    }

    @Test
    void chatCompletion_ShouldReturnNull_WhenStatusIsNot2xx() {
        ResponseEntity<Map> responseEntity = new ResponseEntity<>(new HashMap<>(), HttpStatus.BAD_REQUEST);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class))).thenReturn(responseEntity);

        String result = groqService.chatCompletion(new ArrayList<>(), false);

        assertNull(result);
    }

    @Test
    void chatCompletion_ShouldReturnNull_WhenChoicesMissingOrEmpty() {
        Map<String, Object> noChoices = new HashMap<>();
        ResponseEntity<Map> response1 = new ResponseEntity<>(noChoices, HttpStatus.OK);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class))).thenReturn(response1);

        assertNull(groqService.chatCompletion(new ArrayList<>(), false));

        Map<String, Object> emptyChoices = new HashMap<>();
        emptyChoices.put("choices", new ArrayList<>());
        ResponseEntity<Map> response2 = new ResponseEntity<>(emptyChoices, HttpStatus.OK);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class))).thenReturn(response2);

        assertNull(groqService.chatCompletion(new ArrayList<>(), false));
    }

    @Test
    void chatCompletion_ShouldThrowRuntime_WhenHttpClientErrorOccurs() {
        HttpClientErrorException ex = HttpClientErrorException.create(
                HttpStatus.BAD_REQUEST,
                "Bad Request",
                HttpHeaders.EMPTY,
                "{\"error\":\"invalid\"}".getBytes(),
                null);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class))).thenThrow(ex);

        RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> groqService.chatCompletion(new ArrayList<>(), true));
        assertTrue(thrown.getMessage().contains("Groq API Error"));
    }

    @Test
    void chatCompletion_ShouldFallbackWithoutResponseFormat_WhenJsonValidationFails() {
        HttpClientErrorException ex = HttpClientErrorException.create(
                HttpStatus.BAD_REQUEST,
                "Bad Request",
                HttpHeaders.EMPTY,
                "{\"error\":{\"code\":\"json_validate_failed\",\"message\":\"response_format schema failed\"}}".getBytes(),
                null);

        Map<String, Object> messageMap = new HashMap<>();
        messageMap.put("content", "{\"ok\":true}");
        Map<String, Object> choiceMap = new HashMap<>();
        choiceMap.put("message", messageMap);
        Map<String, Object> bodyMap = new HashMap<>();
        bodyMap.put("choices", List.of(choiceMap));
        ResponseEntity<Map> success = new ResponseEntity<>(bodyMap, HttpStatus.OK);

        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class)))
                .thenThrow(ex)
                .thenReturn(success);

        String result = groqService.chatCompletion(List.of(Map.of("role", "user", "content", "Return json")), true);

        assertEquals("{\"ok\":true}", result);

        ArgumentCaptor<HttpEntity> entityCaptor = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate, times(2)).postForEntity(eq("http://api.groq.com/test"), entityCaptor.capture(), eq(Map.class));

        List<HttpEntity> requests = entityCaptor.getAllValues();
        Map<String, Object> firstBody = (Map<String, Object>) requests.get(0).getBody();
        Map<String, Object> secondBody = (Map<String, Object>) requests.get(1).getBody();

        assertTrue(firstBody.containsKey("response_format"));
        assertFalse(secondBody.containsKey("response_format"));

        List<Map<String, String>> fallbackMessages = (List<Map<String, String>>) secondBody.get("messages");
        String fallbackContent = fallbackMessages.get(fallbackMessages.size() - 1).get("content");
        assertTrue(fallbackContent.contains("Return ONLY valid JSON"));
    }

    @Test
    void chatCompletion_ShouldThrowRuntime_WhenHttpServerErrorOccurs() {
        HttpServerErrorException ex = HttpServerErrorException.create(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "Internal",
                HttpHeaders.EMPTY,
                "{\"error\":\"server\"}".getBytes(),
                null);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class))).thenThrow(ex);

        RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> groqService.chatCompletion(new ArrayList<>(), false));
        assertTrue(thrown.getMessage().contains("Groq API Error"));
    }

    @Test
    void chatCompletion_ShouldRetryOnServerError_AndSucceed() {
        HttpServerErrorException ex = HttpServerErrorException.create(
                HttpStatus.BAD_GATEWAY,
                "Bad Gateway",
                HttpHeaders.EMPTY,
                "{\"error\":\"upstream\"}".getBytes(),
                null);

        Map<String, Object> messageMap = new HashMap<>();
        messageMap.put("content", "ok-after-retry");
        Map<String, Object> choiceMap = new HashMap<>();
        choiceMap.put("message", messageMap);
        Map<String, Object> bodyMap = new HashMap<>();
        bodyMap.put("choices", List.of(choiceMap));
        ResponseEntity<Map> success = new ResponseEntity<>(bodyMap, HttpStatus.OK);

        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class)))
                .thenThrow(ex)
                .thenReturn(success);

        String result = groqService.chatCompletion(List.of(Map.of("role", "user", "content", "ping")), false);

        assertEquals("ok-after-retry", result);
        verify(restTemplate, times(2)).postForEntity(anyString(), any(HttpEntity.class), eq(Map.class));
    }

    @Test
    void chatCompletion_ShouldOpenCircuitAfterThreshold_AndShortCircuitNextCall() {
        ReflectionTestUtils.setField(groqService, "maxAttempts", 1);
        ReflectionTestUtils.setField(groqService, "failureThreshold", 1);
        ReflectionTestUtils.setField(groqService, "openDurationMs", 60000L);

        HttpServerErrorException ex = HttpServerErrorException.create(
                HttpStatus.SERVICE_UNAVAILABLE,
                "Service Unavailable",
                HttpHeaders.EMPTY,
                "{\"error\":\"down\"}".getBytes(),
                null);
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class))).thenThrow(ex);

        assertThrows(RuntimeException.class, () -> groqService.chatCompletion(new ArrayList<>(), false));

        RuntimeException second = assertThrows(RuntimeException.class,
                () -> groqService.chatCompletion(new ArrayList<>(), false));
        assertTrue(second.getMessage().contains("circuit is open"));

        verify(restTemplate, times(1)).postForEntity(anyString(), any(HttpEntity.class), eq(Map.class));
    }

    @Test
    void constructor_ShouldCreateService_WhenInsecureSslEnabled() {
        GroqService insecure = new GroqService(true);
        assertNotNull(insecure);
    }

    @Test
    void chatCompletion_ShouldIncludeJsonResponseFormatAndHeaders_WhenJsonModeEnabled() {
        Map<String, Object> messageMap = new HashMap<>();
        messageMap.put("content", "{\"ok\":true}");
        Map<String, Object> choiceMap = new HashMap<>();
        choiceMap.put("message", messageMap);
        Map<String, Object> bodyMap = new HashMap<>();
        bodyMap.put("choices", List.of(choiceMap));
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class)))
                .thenReturn(new ResponseEntity<>(bodyMap, HttpStatus.OK));

        List<Map<String, String>> messages = List.of(Map.of("role", "user", "content", "hello"));
        String result = groqService.chatCompletion(messages, true);

        assertEquals("{\"ok\":true}", result);

        ArgumentCaptor<HttpEntity> entityCaptor = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).postForEntity(eq("http://api.groq.com/test"), entityCaptor.capture(), eq(Map.class));

        HttpEntity entity = entityCaptor.getValue();
        HttpHeaders headers = entity.getHeaders();
        assertEquals("Bearer test-api-key", headers.getFirst("Authorization"));
        assertEquals("application/json", headers.getContentType().toString());

        Map<String, Object> requestBody = (Map<String, Object>) entity.getBody();
        assertEquals("llama3-8b", requestBody.get("model"));
        assertEquals(messages, requestBody.get("messages"));
        assertEquals(0.7, requestBody.get("temperature"));
        assertTrue(requestBody.containsKey("response_format"));
    }

    @Test
    void chatCompletion_ShouldNotIncludeResponseFormat_WhenJsonModeDisabled() {
        Map<String, Object> messageMap = new HashMap<>();
        messageMap.put("content", "plain text");
        Map<String, Object> choiceMap = new HashMap<>();
        choiceMap.put("message", messageMap);
        Map<String, Object> bodyMap = new HashMap<>();
        bodyMap.put("choices", List.of(choiceMap));
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class)))
                .thenReturn(new ResponseEntity<>(bodyMap, HttpStatus.OK));

        groqService.chatCompletion(List.of(Map.of("role", "user", "content", "hello")), false);

        ArgumentCaptor<HttpEntity> entityCaptor = ArgumentCaptor.forClass(HttpEntity.class);
        verify(restTemplate).postForEntity(eq("http://api.groq.com/test"), entityCaptor.capture(), eq(Map.class));
        Map<String, Object> requestBody = (Map<String, Object>) entityCaptor.getValue().getBody();
        assertFalse(requestBody.containsKey("response_format"));
    }

    @Test
    void chatCompletion_ShouldReturnNull_WhenMessageContentIsMissing() {
        Map<String, Object> messageMap = new HashMap<>();
        Map<String, Object> choiceMap = new HashMap<>();
        choiceMap.put("message", messageMap);
        Map<String, Object> bodyMap = new HashMap<>();
        bodyMap.put("choices", List.of(choiceMap));
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class)))
                .thenReturn(new ResponseEntity<>(bodyMap, HttpStatus.OK));

        String result = groqService.chatCompletion(new ArrayList<>(), false);

        assertNull(result);
    }

    @Test
    void chatCompletion_ShouldWrapException_WhenResponseBodyShapeIsInvalid() {
        Map<String, Object> bodyMap = new HashMap<>();
        bodyMap.put("choices", List.of("not-a-map"));
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class)))
                .thenReturn(new ResponseEntity<>(bodyMap, HttpStatus.OK));

        RuntimeException thrown = assertThrows(RuntimeException.class,
                () -> groqService.chatCompletion(new ArrayList<>(), false));
        assertTrue(thrown.getMessage().contains("Failed to communicate with AI service"));
    }

    @Test
    void insecureConstructor_ShouldCreateHttpsRequestFactoryConnection() throws Exception {
        GroqService insecure = new GroqService(true);
        RestTemplate realTemplate = (RestTemplate) ReflectionTestUtils.getField(insecure, "restTemplate");
        assertNotNull(realTemplate);

        ClientHttpRequest request = realTemplate.getRequestFactory()
                .createRequest(new java.net.URI("https://localhost"), HttpMethod.GET);
        assertNotNull(request);
    }

    @Test
    void chatCompletion_ShouldHandleEmptyApiKey_BranchCoverage() {
        ReflectionTestUtils.setField(groqService, "apiKey", "");

        Map<String, Object> messageMap = new HashMap<>();
        messageMap.put("content", "ok");
        Map<String, Object> choiceMap = new HashMap<>();
        choiceMap.put("message", messageMap);
        Map<String, Object> bodyMap = new HashMap<>();
        bodyMap.put("choices", List.of(choiceMap));
        when(restTemplate.postForEntity(anyString(), any(HttpEntity.class), eq(Map.class)))
                .thenReturn(new ResponseEntity<>(bodyMap, HttpStatus.OK));

        String result = groqService.chatCompletion(List.of(Map.of("role", "user", "content", "ping")), false);

        assertEquals("ok", result);
    }

    @Test
    void createTrustAllManagers_ShouldProvideNoopTrustManager() throws Exception {
        GroqService service = new GroqService(false);

        TrustManager[] managers = service.createTrustAllManagers();
        assertEquals(1, managers.length);
        assertTrue(managers[0] instanceof X509TrustManager);

        X509TrustManager trustManager = (X509TrustManager) managers[0];
        assertNull(trustManager.getAcceptedIssuers());
        trustManager.checkClientTrusted(null, "RSA");
        trustManager.checkServerTrusted(null, "RSA");
    }

    @Test
    void constructor_ShouldFallbackToSecureFactory_WhenInsecureSslInitializationFails() {
        GroqService failingService = new FailingInsecureGroqService();

        RestTemplate template = (RestTemplate) ReflectionTestUtils.getField(failingService, "restTemplate");
        assertNotNull(template);
        assertEquals(SimpleClientHttpRequestFactory.class, template.getRequestFactory().getClass());
    }

    static class FailingInsecureGroqService extends GroqService {
        FailingInsecureGroqService() {
            super(true);
        }

        @Override
        protected void initializeSslContext(SSLContext sslContext, TrustManager[] trustManagers) throws Exception {
            throw new Exception("ssl-init-failed");
        }
    }
}
