package com.ingilizce.calismaapp.security;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class GoogleIdentityServiceTest {

    @SuppressWarnings("unchecked")
    @Test
    void verifyIdToken_ShouldReturnIdentity_WhenPayloadIsValid() {
        AuthSecurityProperties properties = new AuthSecurityProperties();
        properties.setGoogleIdTokenRequired(true);
        properties.setGoogleClientIds(List.of("client-123"));

        RestTemplate restTemplate = mock(RestTemplate.class);
        when(restTemplate.getForObject(any(String.class), eq(Map.class), eq("id-token-ok"))).thenReturn(Map.of(
                "iss", "https://accounts.google.com",
                "aud", "client-123",
                "sub", "google-subject",
                "email", "google@test.com",
                "email_verified", "true",
                "exp", String.valueOf(Instant.now().plusSeconds(300).getEpochSecond())
        ));

        GoogleIdentityService service = new GoogleIdentityService(properties, restTemplate);
        GoogleIdentityService.VerifiedIdentity identity = service.verifyIdToken("id-token-ok");

        assertEquals("google-subject", identity.subject());
        assertEquals("google@test.com", identity.email());
        assertEquals("client-123", identity.audience());
    }

    @SuppressWarnings("unchecked")
    @Test
    void verifyIdToken_ShouldThrowInvalid_WhenAudienceMismatches() {
        AuthSecurityProperties properties = new AuthSecurityProperties();
        properties.setGoogleIdTokenRequired(true);
        properties.setGoogleClientIds(List.of("client-123"));

        RestTemplate restTemplate = mock(RestTemplate.class);
        when(restTemplate.getForObject(any(String.class), eq(Map.class), eq("id-token-bad-aud"))).thenReturn(Map.of(
                "iss", "https://accounts.google.com",
                "aud", "other-client",
                "sub", "google-subject",
                "email", "google@test.com",
                "email_verified", "true",
                "exp", String.valueOf(Instant.now().plusSeconds(300).getEpochSecond())
        ));

        GoogleIdentityService service = new GoogleIdentityService(properties, restTemplate);
        GoogleIdentityService.GoogleIdentityException ex = assertThrows(
                GoogleIdentityService.GoogleIdentityException.class,
                () -> service.verifyIdToken("id-token-bad-aud"));

        assertEquals(GoogleIdentityService.GoogleIdentityException.Code.INVALID_TOKEN, ex.getCode());
    }

    @Test
    void verifyIdToken_ShouldThrowMisconfigured_WhenClientIdsMissingInStrictMode() {
        AuthSecurityProperties properties = new AuthSecurityProperties();
        properties.setGoogleIdTokenRequired(true);
        properties.setGoogleClientIds(List.of());

        RestTemplate restTemplate = mock(RestTemplate.class);
        @SuppressWarnings("unchecked")
        Map<String, Object> payload = Map.of(
                "iss", "https://accounts.google.com",
                "aud", "client-123",
                "sub", "google-subject",
                "email", "google@test.com",
                "email_verified", "true",
                "exp", String.valueOf(Instant.now().plusSeconds(300).getEpochSecond())
        );
        when(restTemplate.getForObject(any(String.class), eq(Map.class), eq("id-token"))).thenReturn(payload);

        GoogleIdentityService service = new GoogleIdentityService(properties, restTemplate);
        GoogleIdentityService.GoogleIdentityException ex = assertThrows(
                GoogleIdentityService.GoogleIdentityException.class,
                () -> service.verifyIdToken("id-token"));

        assertEquals(GoogleIdentityService.GoogleIdentityException.Code.MISCONFIGURED, ex.getCode());
    }

    @Test
    void verifyIdToken_ShouldMapProviderErrors() {
        AuthSecurityProperties properties = new AuthSecurityProperties();
        properties.setGoogleIdTokenRequired(false);

        RestTemplate restTemplate = mock(RestTemplate.class);
        when(restTemplate.getForObject(any(String.class), eq(Map.class), eq("id-token-invalid")))
                .thenThrow(new HttpClientErrorException(HttpStatus.BAD_REQUEST));
        when(restTemplate.getForObject(any(String.class), eq(Map.class), eq("id-token-unavailable")))
                .thenThrow(new ResourceAccessException("timeout"));

        GoogleIdentityService service = new GoogleIdentityService(properties, restTemplate);

        GoogleIdentityService.GoogleIdentityException invalid = assertThrows(
                GoogleIdentityService.GoogleIdentityException.class,
                () -> service.verifyIdToken("id-token-invalid"));
        assertEquals(GoogleIdentityService.GoogleIdentityException.Code.INVALID_TOKEN, invalid.getCode());

        GoogleIdentityService.GoogleIdentityException unavailable = assertThrows(
                GoogleIdentityService.GoogleIdentityException.class,
                () -> service.verifyIdToken("id-token-unavailable"));
        assertEquals(GoogleIdentityService.GoogleIdentityException.Code.PROVIDER_UNAVAILABLE, unavailable.getCode());
    }
}
