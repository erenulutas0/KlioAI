package com.ingilizce.calismaapp.security;

import com.ingilizce.calismaapp.service.LastSeenService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.Instant;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class JwtAuthenticationFilterTest {

    private LastSeenService lastSeenService;

    @BeforeEach
    void setUp() {
        lastSeenService = mock(LastSeenService.class);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void doFilter_ShouldSetAuthentication_WhenBearerTokenIsValid() throws Exception {
        JwtTokenService tokenService = mock(JwtTokenService.class);
        JwtAuthenticationFilter filter = new JwtAuthenticationFilter(tokenService, lastSeenService);

        when(tokenService.parseAccessToken("token-1"))
                .thenReturn(new JwtTokenService.AccessTokenClaims(15L, "ADMIN", "sid-1", Instant.now().plusSeconds(300)));

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader(HttpHeaders.AUTHORIZATION, "Bearer token-1");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        assertNotNull(authentication);
        assertEquals(15L, authentication.getPrincipal());
        assertEquals("sid-1", authentication.getCredentials());
        assertTrue(authentication.getAuthorities().stream()
                .anyMatch(authority -> "ROLE_ADMIN".equals(authority.getAuthority())));
        assertNotNull(authentication.getDetails());
        verify(tokenService).parseAccessToken("token-1");
        // The only place last_seen_at is ever written from: a request that authenticated.
        verify(lastSeenService).touch(15L);
    }

    @Test
    void doFilter_ShouldNotStampLastSeen_WhenTokenIsRejected() throws Exception {
        JwtTokenService tokenService = mock(JwtTokenService.class);
        JwtAuthenticationFilter filter = new JwtAuthenticationFilter(tokenService, lastSeenService);

        when(tokenService.parseAccessToken("token-expired")).thenReturn(null);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader(HttpHeaders.AUTHORIZATION, "Bearer token-expired");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        assertNull(SecurityContextHolder.getContext().getAuthentication());
        verifyNoInteractions(lastSeenService);
    }


    @Test
    void doFilter_ShouldSkipParsing_WhenAuthorizationHeaderMissing() throws Exception {
        JwtTokenService tokenService = mock(JwtTokenService.class);
        JwtAuthenticationFilter filter = new JwtAuthenticationFilter(tokenService, lastSeenService);

        filter.doFilter(new MockHttpServletRequest(), new MockHttpServletResponse(), new MockFilterChain());

        assertNull(SecurityContextHolder.getContext().getAuthentication());
        verifyNoInteractions(tokenService);
    }

    @Test
    void doFilter_ShouldPreserveExistingAuthentication() throws Exception {
        JwtTokenService tokenService = mock(JwtTokenService.class);
        JwtAuthenticationFilter filter = new JwtAuthenticationFilter(tokenService, lastSeenService);

        UsernamePasswordAuthenticationToken existing = new UsernamePasswordAuthenticationToken(
                99L,
                "existing-session",
                List.of());
        SecurityContextHolder.getContext().setAuthentication(existing);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader(HttpHeaders.AUTHORIZATION, "Bearer token-ignored");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        assertSame(existing, SecurityContextHolder.getContext().getAuthentication());
        verifyNoInteractions(tokenService);
    }
}
