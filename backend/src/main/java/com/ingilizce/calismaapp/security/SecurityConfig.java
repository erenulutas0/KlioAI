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
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.http.HttpStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

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

    public SecurityConfig(JwtProperties jwtProperties,
                          JwtAuthenticationFilter jwtAuthenticationFilter,
                          UserHeaderConsistencyFilter userHeaderConsistencyFilter,
                          ObjectMapper objectMapper) {
        this.jwtProperties = jwtProperties;
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
        this.userHeaderConsistencyFilter = userHeaderConsistencyFilter;
        this.objectMapper = objectMapper;
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
                                response.getWriter().write(objectMapper.writeValueAsString(
                                        Map.of("error", "Unauthorized", "success", false)));
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
                            "/api/subscription/plans",
                            "/actuator/health",
                            "/actuator/health/**")
                            .permitAll();
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
