package com.ingilizce.calismaapp.security;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CurrentUserContextTest {

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void getCurrentUserId_ShouldResolveLongAndStringPrincipals() {
        JwtProperties properties = new JwtProperties();
        properties.setEnforceAuth(true);
        CurrentUserContext context = new CurrentUserContext(properties);

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(22L, "sid", List.of()));
        assertEquals(22L, context.getCurrentUserId().orElseThrow());

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("33", "sid", List.of()));
        assertEquals(33L, context.getCurrentUserId().orElseThrow());
    }

    @Test
    void getCurrentUserId_ShouldReturnEmpty_ForInvalidOrMissingAuth() {
        JwtProperties properties = new JwtProperties();
        properties.setEnforceAuth(true);
        CurrentUserContext context = new CurrentUserContext(properties);

        assertTrue(context.getCurrentUserId().isEmpty());

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("not-a-number", "sid", List.of()));
        assertTrue(context.getCurrentUserId().isEmpty());
    }

    @Test
    void hasRole_ShouldMatchExpectedAuthority() {
        JwtProperties properties = new JwtProperties();
        properties.setEnforceAuth(true);
        CurrentUserContext context = new CurrentUserContext(properties);

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(
                        44L,
                        "sid",
                        List.of(new SimpleGrantedAuthority("ROLE_ADMIN"))));

        assertTrue(context.hasRole("ADMIN"));
        assertFalse(context.hasRole("USER"));
    }

    @Test
    void isSelfOrAdmin_ShouldRespectPolicyAndTarget() {
        JwtProperties enforceProperties = new JwtProperties();
        enforceProperties.setEnforceAuth(true);
        CurrentUserContext enforced = new CurrentUserContext(enforceProperties);

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(
                        55L,
                        "sid",
                        List.of(new SimpleGrantedAuthority("ROLE_USER"))));
        assertTrue(enforced.isSelfOrAdmin(55L));
        assertFalse(enforced.isSelfOrAdmin(56L));
        assertFalse(enforced.isSelfOrAdmin(null));
        assertTrue(enforced.shouldEnforceAuthz());

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(
                        77L,
                        "sid",
                        List.of(new SimpleGrantedAuthority("ROLE_ADMIN"))));
        assertTrue(enforced.isSelfOrAdmin(1L));

        JwtProperties bypassProperties = new JwtProperties();
        bypassProperties.setEnforceAuth(false);
        CurrentUserContext bypass = new CurrentUserContext(bypassProperties);
        assertTrue(bypass.isSelfOrAdmin(null));
        assertFalse(bypass.shouldEnforceAuthz());
    }
}
