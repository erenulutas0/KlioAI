package com.ingilizce.calismaapp.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class UserHeaderConsistencyFilterTest {

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void doFilter_ShouldAllow_WhenHeaderMatchesAuthenticatedUser() throws Exception {
        JwtProperties properties = new JwtProperties();
        properties.setEnforceAuth(true);
        UserHeaderConsistencyFilter filter = new UserHeaderConsistencyFilter(properties, new ObjectMapper());

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(10L, "sid", List.of()));

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-User-Id", "10");
        MockFilterChain chain = new MockFilterChain();
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, chain);

        assertNotNull(chain.getRequest());
        assertEquals(200, response.getStatus());
    }

    @Test
    void doFilter_ShouldRejectWithBadRequest_WhenHeaderIsNotNumeric() throws Exception {
        JwtProperties properties = new JwtProperties();
        properties.setEnforceAuth(true);
        UserHeaderConsistencyFilter filter = new UserHeaderConsistencyFilter(properties, new ObjectMapper());

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(10L, "sid", List.of()));

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-User-Id", "not-a-number");
        MockFilterChain chain = new MockFilterChain();
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, chain);

        assertEquals(400, response.getStatus());
        assertNull(chain.getRequest());
        assertTrue(response.getContentAsString().contains("Invalid X-User-Id header"));
    }

    @Test
    void doFilter_ShouldRejectWithForbidden_WhenHeaderMismatchesUser() throws Exception {
        JwtProperties properties = new JwtProperties();
        properties.setEnforceAuth(true);
        UserHeaderConsistencyFilter filter = new UserHeaderConsistencyFilter(properties, new ObjectMapper());

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("15", "sid", List.of()));

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-User-Id", "16");
        MockFilterChain chain = new MockFilterChain();
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, chain);

        assertEquals(403, response.getStatus());
        assertNull(chain.getRequest());
        assertTrue(response.getContentAsString().contains("User identity mismatch"));
    }

    @Test
    void doFilter_ShouldBypass_WhenAuthDisabledOrPrincipalUnparseable() throws Exception {
        JwtProperties disabledProperties = new JwtProperties();
        disabledProperties.setEnforceAuth(false);
        UserHeaderConsistencyFilter disabledFilter = new UserHeaderConsistencyFilter(disabledProperties, new ObjectMapper());

        MockHttpServletRequest disabledRequest = new MockHttpServletRequest();
        disabledRequest.addHeader("X-User-Id", "999");
        MockFilterChain disabledChain = new MockFilterChain();
        disabledFilter.doFilter(disabledRequest, new MockHttpServletResponse(), disabledChain);
        assertNotNull(disabledChain.getRequest());

        JwtProperties enabledProperties = new JwtProperties();
        enabledProperties.setEnforceAuth(true);
        UserHeaderConsistencyFilter enabledFilter = new UserHeaderConsistencyFilter(enabledProperties, new ObjectMapper());

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(new Object(), "sid", List.of()));
        MockHttpServletRequest enabledRequest = new MockHttpServletRequest();
        enabledRequest.addHeader("X-User-Id", "1");
        MockFilterChain enabledChain = new MockFilterChain();
        enabledFilter.doFilter(enabledRequest, new MockHttpServletResponse(), enabledChain);
        assertNotNull(enabledChain.getRequest());
    }
}
