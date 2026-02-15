# Production DDoS Edge Checklist

Bu backend tek başına (uygulama içi rate-limit ile) volumetric DDoS'a dayanıklı değildir.  
Prod için edge koruma zorunludur.

## 1) Edge Koruma (Cloudflare veya eşdeğeri)

1. Domain'i Cloudflare proxy (orange-cloud) arkasına alın.
2. `WAF Managed Rules` aktif edin.
3. `DDoS Protection` ve `Bot Fight Mode` aktif edin.
4. Login/auth endpointleri için ayrı WAF rule yazın:
   - `/api/auth/login`
   - `/api/auth/register`
   - `/api/auth/google-login`
   - `/api/auth/refresh`

## 2) Origin Lockdown

1. Origin (backend) public internete direkt açık olmamalı.
2. Security Group/Firewall'da sadece reverse-proxy/LB IP'lerine izin verin.
3. `8082` gibi backend portlarını world-open bırakmayın.

## 3) Reverse Proxy Limitleri (Nginx/ALB)

1. IP başına connection limiti koyun.
2. IP başına request-rate limiti koyun.
3. Kısa read/header/body timeout değerleri kullanın.
4. Büyük body limitlerini düşürün (gereksiz upload yüzeyini kapatın).

## 4) Header Güveni

1. `X-Forwarded-For` yalnızca trusted proxy zincirinden kabul edilmeli.
2. Uygulama doğrudan internete açıksa `X-Forwarded-For` spoof edilebilir kabul edin.

## 5) Uygulama Katmanı (Mevcut + Öneri)

1. Mevcut auth/AI rate-limitler aktif kalsın.
2. Prod'da Redis fallback politikasını çevresel risk seviyesine göre değerlendirin (`memory` vs `deny`).
3. `google-login` için server-side ID token validation zorunlu kalsın.

## 6) Gözlemlenebilirlik ve Alarm

1. 401/403 spike alarmı ekleyin.
2. 429 spike alarmı ekleyin.
3. RPS, p95 latency, 5xx ve upstream timeout için alarm ekleyin.

## 7) Doğrulama (Go-Live Öncesi)

1. Küçük yük testi ile edge rate-limit davranışını doğrulayın.
2. Origin'e direkt erişimin bloklandığını doğrulayın.
3. `Retry-After` başlıklarının client tarafında düzgün işlendiğini doğrulayın.

## 8) Sonuç

Cloudflare (veya eşdeğer edge katmanı) olmadan "DDoS'a dirençliyiz" denmemeli.
