package com.ingilizce.calismaapp.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import jakarta.servlet.http.HttpServletRequest;

import java.util.Map;

@Configuration
@EnableMethodSecurity
@EnableConfigurationProperties({ JwtProperties.class, AuthSecurityProperties.class })
public class SecurityConfig {
    private static final Logger log = LoggerFactory.getLogger(SecurityConfig.class);

    private final JwtProperties jwtProperties;
    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final UserHeaderConsistencyFilter userHeaderConsistencyFilter;
    private final ObjectMapper objectMapper;

    /// Shared secret Prometheus presents to read /actuator/prometheus.
    ///
    /// Empty means the endpoint stays behind normal authentication, which is
    /// the state this property was written to fix: the metrics endpoint was
    /// switched on in prod, and SecurityConfig permitted only /actuator/health,
    /// so every scrape got 401 and the alert rules had no data at all -- the
    /// alerting looked configured and saw nothing.
    ///
    /// A token rather than an IP allowlist because Prometheus reaches the
    /// backend over the Docker network while Caddy reaches it from the host,
    /// and both arrive from private addresses that cannot be told apart. A
    /// token rather than a separate management port because the public
    /// /actuator/health is load-bearing: the deploy's own smoke test, the
    /// rollout verification and the readiness scripts all call it.
    @Value("${app.ops.metrics-scrape-token:}")
    private String metricsScrapeTokenValue;

    public SecurityConfig(JwtProperties jwtProperties,
                          JwtAuthenticationFilter jwtAuthenticationFilter,
                          UserHeaderConsistencyFilter userHeaderConsistencyFilter,
                          ObjectMapper objectMapper) {
        this.jwtProperties = jwtProperties;
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
        this.userHeaderConsistencyFilter = userHeaderConsistencyFilter;
        this.objectMapper = objectMapper;
    }

    private boolean hasValidScrapeToken(HttpServletRequest request) {
        return new MetricsScrapeToken(metricsScrapeTokenValue)
                .matches(request.getHeader("Authorization"));
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .cors(Customizer.withDefaults())
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint((request, response, authException) -> {
                            if (jwtProperties.isEnforceAuth()) {
                                if (request.getRequestURI().startsWith("/api/subscription/verify/")) {
                                    log.warn("Auth required for subscription verify path={}, method={}",
                                            request.getRequestURI(),
                                            request.getMethod());
                                }
                                response.setStatus(HttpStatus.UNAUTHORIZED.value());
                                response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                                // The reason is load-bearing, not decoration. Without it the
                                // body is just {"error":"Unauthorized"}, and the client has
                                // nothing to distinguish an expired session from a billing
                                // refusal -- it used to read that bare string as a paywall
                                // and send the user, paying subscribers included, to the
                                // subscription page instead of the login screen.
                                response.getWriter().write(objectMapper.writeValueAsString(
                                        Map.of(
                                                "error", "Unauthorized",
                                                "reason", "session-expired",
                                                "success", false)));
                            } else {
                                new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)
                                        .commence(request, response, authException);
                            }
                        })
                        .accessDeniedHandler((request, response, accessDeniedException) -> {
                            if (request.getRequestURI().startsWith("/api/subscription/verify/")) {
                                log.warn("Access denied for subscription verify path={}, method={}",
                                        request.getRequestURI(),
                                        request.getMethod());
                            }
                            response.setStatus(HttpStatus.FORBIDDEN.value());
                            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                            response.getWriter().write(objectMapper.writeValueAsString(
                                    Map.of("error", "Forbidden", "success", false)));
                        }))
                .authorizeHttpRequests(auth -> {
                    auth.requestMatchers(
                            "/api/auth/login",
                            "/api/auth/register",
                            "/api/auth/google-login",
                            "/api/auth/refresh",
                            "/api/auth/password-reset/request",
                            "/api/auth/password-reset/confirm",
                            "/api/auth/email-verification/request",
                            "/api/auth/email-verification/confirm",
                            "/api/subscription/callback/iyzico",
                            "/api/subscription/verify/google",
                            "/api/subscription/google-play/rtdn",
                            "/api/subscription/plans",
                            "/actuator/health",
                            "/actuator/health/**",
                            // Read by an external uptime monitor, which cannot
                            // authenticate. One word and a timestamp; see
                            // AiStatusController for what it deliberately omits.
                            "/api/ops/ai-status")
                            .permitAll();
                    // Readable only by something holding the scrape token. The
                    // check is on the request rather than on an authenticated
                    // principal because Prometheus has no account and should
                    // not need one.
                    auth.requestMatchers("/actuator/prometheus")
                            .access((authentication, context) ->
                                    new AuthorizationDecision(
                                            hasValidScrapeToken(context.getRequest())));
                    if (jwtProperties.isEnforceAuth()) {
                        auth.anyRequest().authenticated();
                    } else {
                        auth.anyRequest().permitAll();
                    }
                })
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class)
                .addFilterAfter(userHeaderConsistencyFilter, JwtAuthenticationFilter.class);

        return http.build();
    }
}
