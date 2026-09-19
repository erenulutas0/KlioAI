package com.ingilizce.calismaapp.security;

import com.ingilizce.calismaapp.service.LastSeenService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpHeaders;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenService jwtTokenService;
    private final LastSeenService lastSeenService;

    public JwtAuthenticationFilter(JwtTokenService jwtTokenService, LastSeenService lastSeenService) {
        this.jwtTokenService = jwtTokenService;
        this.lastSeenService = lastSeenService;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String authHeader = request.getHeader(HttpHeaders.AUTHORIZATION);

        if (authHeader != null && authHeader.startsWith("Bearer ")
                && SecurityContextHolder.getContext().getAuthentication() == null) {
            String token = authHeader.substring(7);
            JwtTokenService.AccessTokenClaims claims = jwtTokenService.parseAccessToken(token);
            if (claims != null) {
                List<SimpleGrantedAuthority> authorities = new ArrayList<>();
                if (claims.role() != null && !claims.role().isBlank()) {
                    authorities.add(new SimpleGrantedAuthority("ROLE_" + claims.role()));
                }

                UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                        claims.userId(),
                        claims.sessionId(),
                        authorities);
                authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(authentication);

                // A token that parses is this learner being here, whatever they then asked
                // for. Here rather than in a controller because there is no one request the
                // app makes on opening, and the answer we want is "which days did they come
                // back", not "which screen did they open". The service swallows its own
                // failures; nothing about a retention metric may cost somebody their lesson.
                lastSeenService.touch(claims.userId());
            }
        }

        filterChain.doFilter(request, response);
    }
}
