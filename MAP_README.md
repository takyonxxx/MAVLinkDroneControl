# Drone Control - Satellite Map Feature

## 🗺️ Harita Özelliği

Bu güncelleme ile drone kontrol uygulamanıza profesyonel bir uydu haritası entegre edildi.

### ✨ Özellikler

#### 📡 Gerçek Zamanlı Drone Takibi
- GPS koordinatlarına göre drone'un canlı konumu
- Heading (yön) bilgisine göre dönen drone ikonu
- Otomatik konum güncelleme

#### 🛤️ Uçuş Yolu Görselleştirmesi
- Drone'un gittiği yolun sarı/altın renkli yumuşak çizgilerle gösterimi
- Performans için optimize edilmiş (maksimum 1000 nokta)
- Minimum 1 metre mesafe filtrelemesi (gereksiz noktaları önler)

#### 📊 Telemetri Overlay Paneli
Harita üzerinde görüntülenen bilgiler:
- **GPS Koordinatları**: Latitude, Longitude (6 ondalık hassasiyet)
- **Altitude**: Yükseklik (metre)
- **Speed**: Hız (m/s)
- **Heading**: Yön (derece)
- **Voltage**: Batarya voltajı (renk kodlu)
  - Yeşil: >11.1V (İyi)
  - Turuncu: 10.5V-11.1V (Orta)
  - Kırmızı: <10.5V (Düşük)
- **Current**: Akım (Amper)
- **GPS Status**: Uydu sayısı (renk kodlu)
  - Yeşil: ≥8 uydu (Mükemmel)
  - Turuncu: 5-7 uydu (İyi)
  - Kırmızı: <5 uydu (Zayıf)

#### 🎯 Kontrol Butonları
- **Center on Drone**: Drone'u haritada ortalar
- **Clear Path**: Uçuş yolunu temizler

#### 🎨 Tasarım
- iPhone 16 Pro için optimize edilmiş arayüz
- iOS/macOS uyumlu (SwiftUI + UIKit hybrid)
- Ultra thin material efektleri (iOS glassmorphism)
- Profesyonel shadow ve glow efektleri
- Dark mode uyumlu

### 📱 Kullanım

1. Uygulamayı açın
2. Alt menüden "Map" sekmesine geçin
3. Drone'a bağlanın
4. GPS fix aldıktan sonra haritada drone'u göreceksiniz
5. Drone hareket ettikçe sarı uçuş yolu oluşacak

### 🔧 Teknik Detaylar

#### Dosyalar
- `EnhancedMapView.swift`: Ana harita görünümü (UIKit + SwiftUI hybrid)
- `MapView.swift`: SwiftUI native map implementasyonu (alternatif)

#### Gereksinimler
- iOS 16.0+
- MapKit framework
- CoreLocation framework

#### Harita Yapılandırması
- **Map Type**: Satellite (Uydu görünümü)
- **Overlay**: MKPolylineRenderer (yumuşak çizgiler)
- **Annotation**: Özel drone marker (heading rotasyonlu)

#### Performans Optimizasyonları
- Maksimum 1000 path point (eski noktalar otomatik silinir)
- 1 metre minimum mesafe filtresi (gereksiz güncellemeler engellenir)
- Efficient overlay rendering (Metal acceleration)

### 🎯 GPS Gereksinimleri

Haritanın düzgün çalışması için:
- Drone'dan `GLOBAL_POSITION_INT` mesajı alınmalı
- GPS fix type ≥ 2 (2D/3D fix)
- En az 5 uydu önerilir

### 🔄 Entegrasyon

Harita, mevcut `MAVLinkManager` singleton'ı ile tamamen entegre:

```swift
// Otomatik güncelleme
.onChange(of: mavlinkManager.latitude) { _ in updateDroneLocation() }
.onChange(of: mavlinkManager.longitude) { _ in updateDroneLocation() }
.onChange(of: mavlinkManager.heading) { _ in updateDroneLocation() }
```

### 🆕 Eklenen Permissions

`Info.plist` dosyasına eklenen:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Bu uygulama, drone'un konumunu harita üzerinde göstermek için konum servislerini kullanır.</string>
```

### 📐 Layout

```
┌─────────────────────────────────────┐
│  Status Bar                         │
│                      ┌─────────────┐│
│                      │ Telemetry   ││
│      Satellite Map   │ Panel       ││
│                      │             ││
│          🛸         │  • GPS      ││
│       ╱──────╲      │  • Alt      ││
│     ╱          ╲    │  • Speed    ││
│   ╱              ╲  │  • Heading  ││
│  •                • │  • Voltage  ││
│   ╲              ╱  │  • Current  ││
│     ╲          ╱    │  • Sats     ││
│       ╲──────╱      └─────────────┘│
│                                     │
│  ⊙                    [Clear Path] │
│ Center                              │
└─────────────────────────────────────┘
```

### 🚀 Gelecek Geliştirmeler

Potansiyel iyileştirmeler:
- Waypoint sistemi (misyon planları)
- Home point marker
- Geofencing (sınır alanları)
- 3D terrain view
- Offline map caching
- Multi-drone support
- Flight replay

### 📞 Destek

Sorularınız için: github.com/yourusername/DroneControl

---

## 🇹🇷 Türkçe Açıklama

Drone kontrol uygulamanıza profesyonel bir uydu haritası eklendi. Harita, drone'unuzun gerçek zamanlı konumunu gösterir, gittiği yolu sarı çizgilerle işaretler ve tüm önemli telemetri bilgilerini (GPS, yükseklik, hız, voltaj, akım) şeffaf bir panel üzerinde gösterir.

iPhone 16 Pro için özel optimize edilmiş, ama tüm iOS ve macOS cihazlarda çalışır. Modern ve profesyonel bir tasarıma sahiptir.

**Kullanım**: Alt menüden "Map" sekmesini seçin ve drone'unuzu takip etmeye başlayın!
