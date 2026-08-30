# KlioAI 1.4.1 — Play Console "Yenilikler / What's new"

1.4.0 (sürüm kodu 439) 29 Ağustos 21:09'da yayına girdi. Bu sürüm onun
üzerine gelen düzeltmeler; yeni özellik yok, o yüzden notlar kısa.

En önemlisi ilk madde: uygulamayı bir süre başka bir dilde **görüntülemek**,
sunucudaki öğrenme profilini değiştiriyordu. Ana dili İspanyolca'ya, seviyeyi
B1'e düşürdüğü görüldü — sonrasında kitapta dokunulan kelimenin anlamı
İspanyolca geliyordu. 439'da bu hata var.

---

## Türkçe

```
• Uygulamayı başka bir dilde görüntülemek, artık ana dilini ve seviyeni değiştirmiyor
• Gramer formülleri Türkçe bilmeyen için de okunabilir hâle geldi
• Dil değiştirdiğinde onay mesajı yeni dilde çıkıyor
• Almanca ve İspanyolca'da ikiye bölünen ayar başlıkları düzeltildi
• Almanca metinlerdeki eksik noktalama işaretleri tamamlandı
```

## English

```
• Viewing the app in another language no longer changes your native language or level
• Grammar formulas are now readable if you do not read Turkish
• The confirmation after switching languages now speaks the new language
• Settings labels no longer break mid-word in German and Spanish
• German text now spells its umlauts instead of writing them out
```

---

## Hangi commit'ler

| | |
|---|---|
| `1f294d5` | profil bozulması — bu sürümün asıl sebebi |
| `c3a6dbd` | dil onayı eski dilde konuşuyordu, etiketler ikiye bölünüyordu |
| `750b73a`, `09ffeca` | gramer formülleri için İngilizce karşılıklar |
| `a45ca9e`, `190e825` | dil seçicilerinin yanlış isimlendirmesi |
| `f42b0bf` | yer tutucu testi (davranış değişikliği yok) |
