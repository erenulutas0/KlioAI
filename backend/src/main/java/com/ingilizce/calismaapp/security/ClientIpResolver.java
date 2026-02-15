package com.ingilizce.calismaapp.security;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class ClientIpResolver {

    private final boolean trustForwardedIpHeader;
    private final String forwardedIpHeaderName;

    public ClientIpResolver(
            @Value("${app.security.trust-forwarded-ip-header:false}") boolean trustForwardedIpHeader,
            @Value("${app.security.forwarded-ip-header-name:X-Forwarded-For}") String forwardedIpHeaderName) {
        this.trustForwardedIpHeader = trustForwardedIpHeader;
        this.forwardedIpHeaderName = forwardedIpHeaderName;
    }

    public String resolve(HttpServletRequest request) {
        try {
            if (request == null) {
                return "unknown";
            }

            if (trustForwardedIpHeader) {
                String forwardedFor = request.getHeader(forwardedIpHeaderName);
                if (forwardedFor != null && !forwardedFor.isBlank()) {
                    String first = forwardedFor.split(",")[0].trim();
                    if (!first.isBlank()) {
                        return first;
                    }
                }
            }

            String remoteAddr = request.getRemoteAddr();
            if (remoteAddr == null || remoteAddr.isBlank()) {
                return "unknown";
            }
            return remoteAddr;
        } catch (Exception ex) {
            return "unknown";
        }
    }
}
