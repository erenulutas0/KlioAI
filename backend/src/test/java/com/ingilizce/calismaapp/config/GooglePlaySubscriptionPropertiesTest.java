package com.ingilizce.calismaapp.config;

import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

class GooglePlaySubscriptionPropertiesTest {

    @Test
    void stringSettersShouldTrimAndNullToEmpty() {
        GooglePlaySubscriptionProperties properties = new GooglePlaySubscriptionProperties();

        properties.setEnabled(true);
        properties.setPackageName(" app.klioai ");
        properties.setServiceAccountFile(" /secure/firebase.json ");
        properties.setTokenUri(" https://oauth.test/token ");
        properties.setPublisherApiBaseUrl(" https://publisher.test ");
        properties.setAcceptGracePeriod(false);
        properties.setAcceptOnHold(true);
        properties.setAccessTokenSkewSeconds(-30);

        assertTrue(properties.isEnabled());
        assertEquals("app.klioai", properties.getPackageName());
        assertEquals("/secure/firebase.json", properties.getServiceAccountFile());
        assertEquals("https://oauth.test/token", properties.getTokenUri());
        assertEquals("https://publisher.test", properties.getPublisherApiBaseUrl());
        assertFalse(properties.isAcceptGracePeriod());
        assertTrue(properties.isAcceptOnHold());
        assertEquals(0, properties.getAccessTokenSkewSeconds());

        properties.setPackageName(null);
        properties.setServiceAccountFile(null);
        properties.setTokenUri(null);
        properties.setPublisherApiBaseUrl(null);

        assertEquals("", properties.getPackageName());
        assertEquals("", properties.getServiceAccountFile());
        assertEquals("", properties.getTokenUri());
        assertEquals("", properties.getPublisherApiBaseUrl());
    }

    @Test
    void productPlanMapShouldFallbackToEmptyMapWhenNullAndPreserveProvidedMap() {
        GooglePlaySubscriptionProperties properties = new GooglePlaySubscriptionProperties();

        properties.setProductPlanMap(null);
        assertTrue(properties.getProductPlanMap().isEmpty());

        Map<String, String> map = new HashMap<>();
        map.put("pro_monthly_subscription", "PREMIUM");
        properties.setProductPlanMap(map);

        assertSame(map, properties.getProductPlanMap());
        assertEquals("PREMIUM", properties.getProductPlanMap().get("pro_monthly_subscription"));
    }
}
