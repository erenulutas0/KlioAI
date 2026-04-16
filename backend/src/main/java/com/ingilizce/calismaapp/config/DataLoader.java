package com.ingilizce.calismaapp.config;

import com.ingilizce.calismaapp.entity.SubscriptionPlan;
import com.ingilizce.calismaapp.repository.SubscriptionPlanRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.math.BigDecimal;

@Configuration
public class DataLoader {
    private static final Logger log = LoggerFactory.getLogger(DataLoader.class);

    @Bean
    CommandLineRunner initDatabase(SubscriptionPlanRepository repository) {
        return args -> {
            ensurePlan(
                    repository,
                    "FREE",
                    BigDecimal.ZERO,
                    "USD",
                    3650,
                    "Base app access. AI available only during free trial window.");

            ensurePlan(
                    repository,
                    "PREMIUM",
                    new BigDecimal("5.00"),
                    "USD",
                    30,
                    "AI access with 50k daily token quota.");

            ensurePlan(
                    repository,
                    "PREMIUM_PLUS",
                    new BigDecimal("10.00"),
                    "USD",
                    30,
                    "AI access with 100k daily token quota.");

            // Keep legacy plans for backward compatibility with existing clients.
            ensurePlan(
                    repository,
                    "PRO_MONTHLY",
                    new BigDecimal("149.99"),
                    "TRY",
                    30,
                    "Legacy monthly plan.");

            ensurePlan(
                    repository,
                    "PRO_ANNUAL",
                    new BigDecimal("999.99"),
                    "TRY",
                    365,
                    "Legacy annual plan.");

            log.info("Subscription plans verified/sealed.");
        };
    }

    private void ensurePlan(SubscriptionPlanRepository repository,
                            String name,
                            BigDecimal price,
                            String currency,
                            int durationDays,
                            String features) {
        repository.findByName(name).orElseGet(() -> {
            SubscriptionPlan plan = new SubscriptionPlan(name, price, durationDays);
            plan.setCurrency(currency);
            plan.setFeatures(features);
            return repository.save(plan);
        });
    }
}
