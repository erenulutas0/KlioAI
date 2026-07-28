package com.ingilizce.calismaapp.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.Map;

/**
 * Gunluk icerik servislerinin ortak koruma noktasi.
 *
 * <p>AI uretimi basarisiz oldugunda servisler kullaniciyi bos ekranla birakmamak
 * icin {@code fallback=true} isaretli yedek bir payload uretiyor. Bu payload
 * gosterilebilir ama <b>kalici olarak cache'lenmemeli</b>: {@code daily_content}
 * tablosuna yazilirsa o gun+tur icin sonraki her istek cache dalina duser ve
 * gercek icerik bir daha hic uretilmez - tek bir gecici hata gunu zehirler.
 */
public final class DailyContentFallbackSupport {

    private DailyContentFallbackSupport() {
    }

    /** Payload JSON'i {@code fallback=true} tasiyor mu? Coz+kontrol et. */
    public static boolean isFallbackPayload(String payloadJson, ObjectMapper objectMapper) {
        if (payloadJson == null || payloadJson.isBlank() || objectMapper == null) {
            // Icerigi dogrulayamiyorsak cache'lememek daha guvenli.
            return true;
        }
        try {
            Map<String, Object> payload =
                    objectMapper.readValue(payloadJson, new TypeReference<Map<String, Object>>() {
                    });
            return isFallbackPayload(payload);
        } catch (Exception e) {
            return true;
        }
    }

    /** Cozulmus payload {@code fallback=true} tasiyor mu? */
    public static boolean isFallbackPayload(Map<String, Object> payload) {
        if (payload == null || payload.isEmpty()) {
            return true;
        }
        Object flag = payload.get("fallback");
        if (flag instanceof Boolean bool) {
            return bool;
        }
        return flag != null && Boolean.parseBoolean(flag.toString().trim());
    }
}
