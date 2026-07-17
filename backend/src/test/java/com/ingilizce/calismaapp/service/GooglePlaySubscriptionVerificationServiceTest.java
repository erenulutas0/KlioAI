package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.config.GooglePlaySubscriptionProperties;
import com.ingilizce.calismaapp.service.GooglePlaySubscriptionVerificationService.GooglePlayVerificationException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPairGenerator;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class GooglePlaySubscriptionVerificationServiceTest {

    private static final Instant NOW = Instant.parse("2026-07-06T00:00:00Z");

    @TempDir
    Path tempDir;

    private GooglePlaySubscriptionProperties properties;
    private RestTemplate restTemplate;
    private GooglePlaySubscriptionVerificationService service;

    @BeforeEach
    void setUp() throws Exception {
        properties = new GooglePlaySubscriptionProperties();
        properties.setEnabled(true);
        properties.setPackageName("com.VocabMaster");
        properties.setPublisherApiBaseUrl("https://publisher.test");
        properties.setTokenUri("https://oauth.test/token");
        properties.setServiceAccountFile(writeServiceAccountFile());
        properties.setProductPlanMap(Map.of(
                "pro_monthly_subscription", "PREMIUM",
                "monthly", "PREMIUM",
                "pro_annual_subscription", "PREMIUM_PLUS"));

        restTemplate = mock(RestTemplate.class);
        service = new GooglePlaySubscriptionVerificationService(
                properties,
                restTemplate,
                new ObjectMapper(),
                Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void fetchSubscriptionStateShouldRejectDisabledVerificationBeforeNetwork() {
        properties.setEnabled(false);

        GooglePlayVerificationException ex = assertThrows(
                GooglePlayVerificationException.class,
                () -> service.fetchSubscriptionState("token-1", null));

        assertEquals(GooglePlayVerificationException.Code.MISCONFIGURED, ex.getCode());
        verifyNoInteractions(restTemplate);
    }

    @Test
    void fetchSubscriptionStateShouldRejectBlankPurchaseTokenBeforeNetwork() {
        GooglePlayVerificationException ex = assertThrows(
                GooglePlayVerificationException.class,
                () -> service.fetchSubscriptionState("  ", null));

        assertEquals(GooglePlayVerificationException.Code.INVALID_PURCHASE, ex.getCode());
        verifyNoInteractions(restTemplate);
    }

    @Test
    void fetchSubscriptionStateShouldParseProductsExpiryAndUsePackageFallback() {
        stubOAuthToken("access-1", "3600");
        Map<String, Object> payload = Map.of(
                "subscriptionState", "SUBSCRIPTION_STATE_ACTIVE",
                "latestOrderId", "GPA.123",
                "lineItems", List.of(
                        Map.of(
                                "productId", "pro_monthly_subscription",
                                "expiryTime", NOW.plusSeconds(3600).toString(),
                                "offerDetails", Map.of("basePlanId", "monthly")),
                        Map.of(
                                "productId", "ignored-invalid-expiry",
                                "expiryTime", "not-an-instant")));
        when(restTemplate.exchange(
                anyString(),
                eq(HttpMethod.GET),
                any(HttpEntity.class),
                eq(Map.class),
                eq("com.VocabMaster"),
                eq("token-1")))
                .thenReturn(new ResponseEntity<>(payload, HttpStatus.OK));

        GooglePlaySubscriptionVerificationService.VerificationResult result =
                service.fetchSubscriptionState("token-1", " ");

        assertEquals("com.VocabMaster", result.packageName());
        assertEquals("token-1", result.purchaseToken());
        assertEquals("SUBSCRIPTION_STATE_ACTIVE", result.subscriptionState());
        assertEquals("GPA.123", result.latestOrderId());
        assertEquals(NOW.plusSeconds(3600), result.expiryTime());
        assertEquals(List.of("pro_monthly_subscription", "monthly", "ignored-invalid-expiry"), result.productKeys());
    }

    @Test
    void verifySubscriptionShouldRejectInactiveOrExpiredState() {
        stubOAuthToken("access-1", "3600");
        stubSubscriptionPayload(Map.of(
                "subscriptionState", "SUBSCRIPTION_STATE_CANCELED",
                "lineItems", List.of(Map.of("productId", "pro_monthly_subscription"))));

        GooglePlayVerificationException inactive = assertThrows(
                GooglePlayVerificationException.class,
                () -> service.verifySubscription("token-1", "com.VocabMaster"));

        assertEquals(GooglePlayVerificationException.Code.INVALID_PURCHASE, inactive.getCode());

        stubSubscriptionPayload(Map.of(
                "subscriptionState", "SUBSCRIPTION_STATE_ACTIVE",
                "lineItems", List.of(Map.of(
                        "productId", "pro_monthly_subscription",
                        "expiryTime", NOW.minusSeconds(1).toString()))));

        GooglePlayVerificationException expired = assertThrows(
                GooglePlayVerificationException.class,
                () -> service.verifySubscription("token-1", "com.VocabMaster"));

        assertEquals(GooglePlayVerificationException.Code.INVALID_PURCHASE, expired.getCode());
    }

    @Test
    void stateEligibilityShouldRespectGraceAndOnHoldProperties() {
        assertTrue(service.isStateEligibleForAccess("SUBSCRIPTION_STATE_ACTIVE"));
        assertTrue(service.isStateEligibleForAccess("SUBSCRIPTION_STATE_IN_GRACE_PERIOD"));
        assertFalse(service.isStateEligibleForAccess("SUBSCRIPTION_STATE_ON_HOLD"));
        assertFalse(service.isStateEligibleForAccess(""));

        properties.setAcceptGracePeriod(false);
        properties.setAcceptOnHold(true);

        assertFalse(service.isStateEligibleForAccess("SUBSCRIPTION_STATE_IN_GRACE_PERIOD"));
        assertTrue(service.isStateEligibleForAccess("SUBSCRIPTION_STATE_ON_HOLD"));
    }

    @Test
    void resolvePlanNameShouldPreferRequestedProductThenVerificationKeysCaseInsensitively() {
        GooglePlaySubscriptionVerificationService.VerificationResult verification =
                new GooglePlaySubscriptionVerificationService.VerificationResult(
                        "com.VocabMaster",
                        "token-1",
                        "SUBSCRIPTION_STATE_ACTIVE",
                        "GPA.123",
                        NOW.plusSeconds(3600),
                        List.of("MONTHLY"));

        assertEquals("PREMIUM_PLUS", service.resolvePlanName(verification, "PRO_ANNUAL_SUBSCRIPTION"));
        assertEquals("PREMIUM", service.resolvePlanName(verification, null));
        assertEquals(null, service.resolvePlanName(null, "monthly"));
    }

    @Test
    void fetchSubscriptionStateShouldMapProviderHttpFailures() {
        stubOAuthToken("access-1", "3600");

        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(HttpEntity.class), eq(Map.class), anyString(), anyString()))
                .thenThrow(new HttpClientErrorException(
                        HttpStatus.FORBIDDEN,
                        "Forbidden",
                        "{\"error\":\"permissionDenied\"}".getBytes(StandardCharsets.UTF_8),
                        StandardCharsets.UTF_8));

        GooglePlayVerificationException forbidden = assertThrows(
                GooglePlayVerificationException.class,
                () -> service.fetchSubscriptionState("token-1", "com.VocabMaster"));
        assertEquals(GooglePlayVerificationException.Code.MISCONFIGURED, forbidden.getCode());

        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(HttpEntity.class), eq(Map.class), anyString(), anyString()))
                .thenThrow(new HttpClientErrorException(HttpStatus.NOT_FOUND));
        GooglePlayVerificationException notFound = assertThrows(
                GooglePlayVerificationException.class,
                () -> service.fetchSubscriptionState("token-1", "com.VocabMaster"));
        assertEquals(GooglePlayVerificationException.Code.INVALID_PURCHASE, notFound.getCode());

        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(HttpEntity.class), eq(Map.class), anyString(), anyString()))
                .thenThrow(new HttpServerErrorException(HttpStatus.BAD_GATEWAY));
        GooglePlayVerificationException serverError = assertThrows(
                GooglePlayVerificationException.class,
                () -> service.fetchSubscriptionState("token-1", "com.VocabMaster"));
        assertEquals(GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE, serverError.getCode());
    }

    @Test
    void fetchAccessTokenShouldRejectMissingAccessToken() {
        when(restTemplate.postForObject(eq("https://oauth.test/token"), any(HttpEntity.class), eq(Map.class)))
                .thenReturn(Map.of("expires_in", "3600"));

        GooglePlayVerificationException ex = assertThrows(
                GooglePlayVerificationException.class,
                () -> service.fetchSubscriptionState("token-1", "com.VocabMaster"));

        assertEquals(GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE, ex.getCode());
    }

    @Test
    void fetchAccessTokenShouldMapOAuthConnectivityFailures() {
        when(restTemplate.postForObject(eq("https://oauth.test/token"), any(HttpEntity.class), eq(Map.class)))
                .thenThrow(new ResourceAccessException("timeout"));

        GooglePlayVerificationException ex = assertThrows(
                GooglePlayVerificationException.class,
                () -> service.fetchSubscriptionState("token-1", "com.VocabMaster"));

        assertEquals(GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE, ex.getCode());
    }

    @Test
    void fetchSubscriptionStateShouldReuseCachedOAuthToken() {
        stubOAuthToken("access-1", "3600");
        stubSubscriptionPayload(Map.of(
                "subscriptionState", "SUBSCRIPTION_STATE_ACTIVE",
                "lineItems", List.of(Map.of(
                        "productId", "pro_monthly_subscription",
                        "expiryTime", NOW.plusSeconds(3600).toString()))));

        service.fetchSubscriptionState("token-1", "com.VocabMaster");
        service.fetchSubscriptionState("token-2", "com.VocabMaster");

        verify(restTemplate).postForObject(eq("https://oauth.test/token"), any(HttpEntity.class), eq(Map.class));
    }

    private void stubOAuthToken(String token, String expiresIn) {
        when(restTemplate.postForObject(eq("https://oauth.test/token"), any(HttpEntity.class), eq(Map.class)))
                .thenReturn(Map.of("access_token", token, "expires_in", expiresIn));
    }

    private void stubSubscriptionPayload(Map<String, Object> payload) {
        when(restTemplate.exchange(anyString(), eq(HttpMethod.GET), any(HttpEntity.class), eq(Map.class), anyString(), anyString()))
                .thenReturn(new ResponseEntity<>(payload, HttpStatus.OK));
    }

    private String writeServiceAccountFile() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        String privateKey = Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
                .encodeToString(generator.generateKeyPair().getPrivate().getEncoded());
        String pem = "-----BEGIN PRIVATE KEY-----\n" + privateKey + "\n-----END PRIVATE KEY-----\n";
        Path path = tempDir.resolve("google-service-account.json");
        String json = new ObjectMapper().writeValueAsString(Map.of(
                "client_email", "service@example.iam.gserviceaccount.com",
                "private_key", pem,
                "token_uri", "https://oauth.test/token"));
        Files.writeString(path, json, StandardCharsets.UTF_8);
        return path.toString();
    }
}
