package com.ingilizce.calismaapp.security;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ClientIpResolverTest {

    @Test
    void resolve_ShouldUseRemoteAddr_WhenForwardedHeaderTrustDisabled() {
        ClientIpResolver resolver = new ClientIpResolver(false, "X-Forwarded-For");
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRemoteAddr("10.0.0.10");
        request.addHeader("X-Forwarded-For", "203.0.113.1");

        String ip = resolver.resolve(request);

        assertEquals("10.0.0.10", ip);
    }

    @Test
    void resolve_ShouldUseFirstForwardedIp_WhenForwardedHeaderTrustEnabled() {
        ClientIpResolver resolver = new ClientIpResolver(true, "X-Forwarded-For");
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRemoteAddr("10.0.0.10");
        request.addHeader("X-Forwarded-For", "203.0.113.1, 203.0.113.2");

        String ip = resolver.resolve(request);

        assertEquals("203.0.113.1", ip);
    }
}
