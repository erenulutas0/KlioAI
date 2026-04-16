package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ingilizce.calismaapp.config.GooglePlaySubscriptionProperties;
import io.jsonwebtoken.Jwts;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.*;

@Service
public class GooglePlaySubscriptionVerificationService {

    public record VerificationResult(
            String packageName,
            String purchaseToken,
            String subscriptionState,
            String latestOrderId,
            Instant expiryTime,
            List<String> productKeys) {
    }

    public static class GooglePlayVerificationException extends RuntimeException {
        public enum Code {
            MISCONFIGURED,
            INVALID_PURCHASE,
            PROVIDER_UNAVAILABLE
        }

        private final Code code;

        public GooglePlayVerificationException(Code code, String message) {
            super(message);
            this.code = code;
        }

        public Code getCode() {
            return code;
        }
    }

    private record ServiceAccount(String clientEmail, PrivateKey privateKey, String tokenUri) {
    }

    private record OAuthAccessToken(String token, Instant expiresAt) {
    }

    private static final String OAUTH_SCOPE_ANDROID_PUBLISHER = "https://www.googleapis.com/auth/androidpublisher";
    private static final Set<String> ALWAYS_ALLOWED_STATES = Set.of("SUBSCRIPTION_STATE_ACTIVE");
    private static final Set<String> GRACE_STATES = Set.of("SUBSCRIPTION_STATE_IN_GRACE_PERIOD");
    private static final Set<String> ON_HOLD_STATES = Set.of("SUBSCRIPTION_STATE_ON_HOLD");

    private final GooglePlaySubscriptionProperties properties;
    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    private volatile ServiceAccount cachedServiceAccount;
    private volatile OAuthAccessToken cachedAccessToken;

    @Autowired
    public GooglePlaySubscriptionVerificationService(GooglePlaySubscriptionProperties properties,
                                                     RestTemplateBuilder restTemplateBuilder) {
        this(
                properties,
                restTemplateBuilder
                        .setConnectTimeout(Duration.ofSeconds(5))
                        .setReadTimeout(Duration.ofSeconds(10))
                        .build(),
                new ObjectMapper(),
                Clock.systemUTC());
    }

    GooglePlaySubscriptionVerificationService(GooglePlaySubscriptionProperties properties,
                                              RestTemplate restTemplate,
                                              ObjectMapper objectMapper,
                                              Clock clock) {
        this.properties = properties;
        this.restTemplate = restTemplate;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    @SuppressWarnings("unchecked")
    public VerificationResult verifySubscription(String purchaseToken, String packageNameOverride) {
        VerificationResult snapshot = fetchSubscriptionState(purchaseToken, packageNameOverride);
        String subscriptionState = snapshot.subscriptionState();
        if (!isAllowedSubscriptionState(subscriptionState)) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.INVALID_PURCHASE,
                    "Subscription is not active");
        }
        Instant expiry = snapshot.expiryTime();
        if (expiry != null && expiry.isBefore(clock.instant())) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.INVALID_PURCHASE,
                    "Subscription is expired");
        }
        return snapshot;
    }

    @SuppressWarnings("unchecked")
    public VerificationResult fetchSubscriptionState(String purchaseToken, String packageNameOverride) {
        if (!properties.isEnabled()) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.MISCONFIGURED,
                    "Google Play verification is disabled");
        }
        if (purchaseToken == null || purchaseToken.isBlank()) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.INVALID_PURCHASE,
                    "Missing purchaseToken");
        }

        String packageName = trimToEmpty(packageNameOverride);
        if (packageName.isEmpty()) {
            packageName = trimToEmpty(properties.getPackageName());
        }
        if (packageName.isEmpty()) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.MISCONFIGURED,
                    "Google Play package name is not configured");
        }

        String baseApi = trimToEmpty(properties.getPublisherApiBaseUrl());
        if (baseApi.isEmpty()) {
            baseApi = "https://androidpublisher.googleapis.com";
        }
        String url = baseApi + "/androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}";

        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(getAccessToken());

        Map<String, Object> response;
        try {
            ResponseEntity<Map> entity = restTemplate.exchange(
                    url,
                    HttpMethod.GET,
                    new HttpEntity<>(headers),
                    Map.class,
                    packageName,
                    purchaseToken);
            response = entity.getBody();
        } catch (HttpStatusCodeException ex) {
            String detail = summarizeHttpError(ex);
            if (ex.getStatusCode().is4xxClientError()) {
                if (ex.getStatusCode() == HttpStatus.UNAUTHORIZED || ex.getStatusCode() == HttpStatus.FORBIDDEN) {
                    throw new GooglePlayVerificationException(
                            GooglePlayVerificationException.Code.MISCONFIGURED,
                            "Google Play permission/auth failed: " + detail);
                }
                throw new GooglePlayVerificationException(
                        GooglePlayVerificationException.Code.INVALID_PURCHASE,
                        "Google Play purchase token rejected: " + detail);
            }
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE,
                    "Google Play verification unavailable: " + detail);
        } catch (ResourceAccessException ex) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE,
                    "Google Play verification unreachable");
        } catch (RestClientException ex) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE,
                    "Google Play verification failed");
        }

        if (response == null || response.isEmpty()) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.INVALID_PURCHASE,
                    "Empty Google Play verification response");
        }

        List<String> productKeys = extractProductKeys(response);
        Instant expiry = extractMaxExpiry(response);

        return new VerificationResult(
                packageName,
                purchaseToken,
                asString(response.get("subscriptionState")),
                asString(response.get("latestOrderId")),
                expiry,
                productKeys);
    }

    public boolean isStateEligibleForAccess(String state) {
        return isAllowedSubscriptionState(state);
    }

    public String resolvePlanName(VerificationResult verificationResult, String requestedProductId) {
        if (verificationResult == null) {
            return null;
        }
        if (properties.getProductPlanMap() == null || properties.getProductPlanMap().isEmpty()) {
            return null;
        }

        LinkedHashSet<String> candidates = new LinkedHashSet<>();
        String requested = normalizeKey(requestedProductId);
        if (!requested.isEmpty()) {
            candidates.add(requested);
        }
        if (verificationResult.productKeys() != null) {
            for (String key : verificationResult.productKeys()) {
                String normalized = normalizeKey(key);
                if (!normalized.isEmpty()) {
                    candidates.add(normalized);
                }
            }
        }

        for (String candidate : candidates) {
            String mapped = findMappedPlan(candidate);
            if (mapped != null && !mapped.isBlank()) {
                return mapped.trim();
            }
        }
        return null;
    }

    private String getAccessToken() {
        OAuthAccessToken cached = cachedAccessToken;
        Instant now = clock.instant();
        if (cached != null && cached.expiresAt().isAfter(now.plusSeconds(properties.getAccessTokenSkewSeconds()))) {
            return cached.token();
        }
        synchronized (this) {
            OAuthAccessToken again = cachedAccessToken;
            Instant nowInside = clock.instant();
            if (again != null && again.expiresAt().isAfter(nowInside.plusSeconds(properties.getAccessTokenSkewSeconds()))) {
                return again.token();
            }
            OAuthAccessToken refreshed = fetchAccessToken();
            cachedAccessToken = refreshed;
            return refreshed.token();
        }
    }

    @SuppressWarnings("unchecked")
    private OAuthAccessToken fetchAccessToken() {
        ServiceAccount serviceAccount = getServiceAccount();
        Instant now = clock.instant();
        Instant exp = now.plusSeconds(3600);

        String assertion = Jwts.builder()
                .issuer(serviceAccount.clientEmail())
                .claim("aud", serviceAccount.tokenUri())
                .claim("scope", OAUTH_SCOPE_ANDROID_PUBLISHER)
                .issuedAt(Date.from(now))
                .expiration(Date.from(exp))
                .signWith(serviceAccount.privateKey(), Jwts.SIG.RS256)
                .compact();

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer");
        form.add("assertion", assertion);

        Map<String, Object> response;
        try {
            response = restTemplate.postForObject(
                    serviceAccount.tokenUri(),
                    new HttpEntity<>(form, headers),
                    Map.class);
        } catch (HttpStatusCodeException ex) {
            String detail = summarizeHttpError(ex);
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE,
                    "Google OAuth token request failed: " + detail);
        } catch (ResourceAccessException ex) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE,
                    "Google OAuth token endpoint unreachable");
        } catch (RestClientException ex) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE,
                    "Google OAuth token request error");
        }

        String accessToken = response != null ? asString(response.get("access_token")) : "";
        long expiresIn = parseLong(response != null ? response.get("expires_in") : null, 3600L);
        if (accessToken.isBlank()) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.PROVIDER_UNAVAILABLE,
                    "Google OAuth response missing access_token");
        }

        return new OAuthAccessToken(accessToken, now.plusSeconds(Math.max(60L, expiresIn)));
    }

    private ServiceAccount getServiceAccount() {
        ServiceAccount cached = cachedServiceAccount;
        if (cached != null) {
            return cached;
        }
        synchronized (this) {
            if (cachedServiceAccount != null) {
                return cachedServiceAccount;
            }

            String serviceAccountFile = trimToEmpty(properties.getServiceAccountFile());
            if (serviceAccountFile.isEmpty()) {
                throw new GooglePlayVerificationException(
                        GooglePlayVerificationException.Code.MISCONFIGURED,
                        "Google Play service account file is not configured");
            }

            Map<String, Object> json;
            try {
                String raw = Files.readString(Path.of(serviceAccountFile));
                json = objectMapper.readValue(raw, new TypeReference<>() {
                });
            } catch (Exception ex) {
                throw new GooglePlayVerificationException(
                        GooglePlayVerificationException.Code.MISCONFIGURED,
                        "Unable to read Google service account file");
            }

            String clientEmail = asString(json.get("client_email"));
            String privateKeyPem = asString(json.get("private_key"));
            String tokenUri = trimToEmpty(properties.getTokenUri());
            if (tokenUri.isEmpty()) {
                tokenUri = asString(json.get("token_uri"));
            }

            if (clientEmail.isBlank() || privateKeyPem.isBlank() || tokenUri.isBlank()) {
                throw new GooglePlayVerificationException(
                        GooglePlayVerificationException.Code.MISCONFIGURED,
                        "Google service account file is missing required fields");
            }

            PrivateKey privateKey = parsePrivateKey(privateKeyPem);
            cachedServiceAccount = new ServiceAccount(clientEmail, privateKey, tokenUri);
            return cachedServiceAccount;
        }
    }

    private PrivateKey parsePrivateKey(String pem) {
        String normalizedPem = pem
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s+", "");
        try {
            byte[] decoded = Base64.getDecoder().decode(normalizedPem);
            PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(decoded);
            return KeyFactory.getInstance("RSA").generatePrivate(keySpec);
        } catch (Exception ex) {
            throw new GooglePlayVerificationException(
                    GooglePlayVerificationException.Code.MISCONFIGURED,
                    "Google service account private key is invalid");
        }
    }

    @SuppressWarnings("unchecked")
    private List<String> extractProductKeys(Map<String, Object> payload) {
        LinkedHashSet<String> keys = new LinkedHashSet<>();
        Object lineItemsRaw = payload.get("lineItems");
        if (lineItemsRaw instanceof List<?> lineItems) {
            for (Object lineItemRaw : lineItems) {
                if (!(lineItemRaw instanceof Map<?, ?> itemMapRaw)) {
                    continue;
                }
                Map<String, Object> itemMap = (Map<String, Object>) itemMapRaw;
                String productId = asString(itemMap.get("productId"));
                if (!productId.isBlank()) {
                    keys.add(productId);
                }
                Object offerDetailsRaw = itemMap.get("offerDetails");
                if (offerDetailsRaw instanceof Map<?, ?> offerMapRaw) {
                    Map<String, Object> offerMap = (Map<String, Object>) offerMapRaw;
                    String basePlanId = asString(offerMap.get("basePlanId"));
                    if (!basePlanId.isBlank()) {
                        keys.add(basePlanId);
                    }
                }
            }
        }
        return new ArrayList<>(keys);
    }

    @SuppressWarnings("unchecked")
    private Instant extractMaxExpiry(Map<String, Object> payload) {
        Instant max = null;
        Object lineItemsRaw = payload.get("lineItems");
        if (!(lineItemsRaw instanceof List<?> lineItems)) {
            return null;
        }
        for (Object lineItemRaw : lineItems) {
            if (!(lineItemRaw instanceof Map<?, ?> itemMapRaw)) {
                continue;
            }
            Map<String, Object> itemMap = (Map<String, Object>) itemMapRaw;
            String expiryRaw = asString(itemMap.get("expiryTime"));
            if (expiryRaw.isBlank()) {
                continue;
            }
            try {
                Instant expiry = Instant.parse(expiryRaw);
                if (max == null || expiry.isAfter(max)) {
                    max = expiry;
                }
            } catch (DateTimeParseException ignored) {
                // ignore invalid expiry values from upstream payload
            }
        }
        return max;
    }

    private boolean isAllowedSubscriptionState(String state) {
        if (state == null || state.isBlank()) {
            return false;
        }
        if (ALWAYS_ALLOWED_STATES.contains(state)) {
            return true;
        }
        if (properties.isAcceptGracePeriod() && GRACE_STATES.contains(state)) {
            return true;
        }
        return properties.isAcceptOnHold() && ON_HOLD_STATES.contains(state);
    }

    private String findMappedPlan(String productKey) {
        if (productKey == null || productKey.isBlank()) {
            return null;
        }
        String normalized = normalizeKey(productKey);
        for (Map.Entry<String, String> entry : properties.getProductPlanMap().entrySet()) {
            if (normalizeKey(entry.getKey()).equals(normalized)) {
                return entry.getValue();
            }
        }
        return null;
    }

    private String asString(Object value) {
        if (value == null) {
            return "";
        }
        return String.valueOf(value).trim();
    }

    private String trimToEmpty(String value) {
        if (value == null) {
            return "";
        }
        return value.trim();
    }

    private String normalizeKey(String value) {
        return trimToEmpty(value).toLowerCase(Locale.ROOT);
    }

    private long parseLong(Object value, long defaultValue) {
        if (value == null) {
            return defaultValue;
        }
        try {
            return Long.parseLong(String.valueOf(value).trim());
        } catch (NumberFormatException ignored) {
            return defaultValue;
        }
    }

    private String summarizeHttpError(HttpStatusCodeException ex) {
        String body = ex.getResponseBodyAsString();
        if (body == null) {
            body = "";
        }
        body = body.replaceAll("\\s+", " ").trim();
        if (body.length() > 300) {
            body = body.substring(0, 300) + "...";
        }
        if (body.isEmpty()) {
            return String.valueOf(ex.getStatusCode().value());
        }
        return ex.getStatusCode().value() + " " + body;
    }
}
