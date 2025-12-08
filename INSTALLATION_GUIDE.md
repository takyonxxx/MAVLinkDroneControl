# Harita Özelliği Kurulum Rehberi

## 📦 Kurulum Adımları

### 1. Dosyaları Projeye Ekleyin

#### a) EnhancedMapView.swift
```
DroneControl/Views/EnhancedMapView.swift
```
Bu dosyayı Xcode'da `Views` klasörüne sürükleyin.

#### b) MapView.swift (Opsiyonel - Alternatif)
```
DroneControl/Views/MapView.swift
```
Bu da alternatif bir implementasyon. İsterseniz sadece EnhancedMapView kullanabilirsiniz.

#### c) ContentView.swift
Mevcut `ContentView.swift` dosyanızı verilen yeni versiyonla değiştirin.

#### d) Info.plist
Mevcut `Info.plist` dosyanızı verilen yeni versiyonla değiştirin veya aşağıdaki satırları ekleyin:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Bu uygulama, drone'un konumunu harita üzerinde göstermek için konum servislerini kullanır.</string>
```

### 2. Xcode Build Settings

Projenizin MapKit framework'üne erişimi olduğundan emin olun:

1. Xcode'da projenizi açın
2. Target'ınızı seçin
3. "Frameworks, Libraries, and Embedded Content" bölümüne gidin
4. Eğer yoksa `MapKit.framework` ekleyin (genellikle otomatik eklenir)

### 3. Test Edin

1. Projeyi build edin (⌘+B)
2. Simulator veya gerçek cihazda çalıştırın
3. Alt menüden "Map" sekmesine geçin
4. Drone'a bağlanın
5. GPS fix aldıktan sonra haritada göreceksiniz

## 🔍 Sorun Giderme

### Harita görünmüyor
- Info.plist'te konum izni var mı kontrol edin
- Console'da hata mesajlarını inceleyin
- GPS fix alınıp alınmadığını Dashboard'dan kontrol edin

### Drone ikonu dönmüyor
- MAVLinkManager'dan heading değeri geldiğinden emin olun
- VFR_HUD mesajının alındığını kontrol edin

### Uçuş yolu çizilmiyor
- En az 2 nokta gereklidir
- GPS koordinatları 0,0 olmamalı
- Minimum 1 metre hareket gereklidir

### Build hataları
- Swift version: 5.0+
- iOS Deployment Target: 16.0+
- Tüm dosyaların Target Membership'i doğru mu?

## ✅ Kontrol Listesi

- [ ] EnhancedMapView.swift projeye eklendi
- [ ] ContentView.swift güncellendi
- [ ] Info.plist güncellendi
- [ ] MapKit framework var
- [ ] Proje build oluyor
- [ ] Map sekmesi görünüyor
- [ ] Drone bağlanınca haritada görünüyor
- [ ] Telemetri paneli çalışıyor
- [ ] Uçuş yolu çiziliyor
- [ ] Clear Path butonu çalışıyor
- [ ] Center on Drone butonu çalışıyor

## 🎯 Özelleştirme

### Renkleri değiştirmek
`EnhancedMapView.swift` içinde:

```swift
// Uçuş yolu rengi
renderer.strokeColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.9)

// Telemetri panel renkleri
.foregroundColor(.cyan) // Değiştirin
```

### Harita başlangıç konumu
```swift
// Ankara yerine farklı bir konum
let region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784), // İstanbul
    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
)
```

### Path uzunluğu
```swift
private let maxPathPoints = 1000 // İstediğiniz değer
```

## 📱 Cihaz Gereksinimleri

- iOS 16.0 veya üzeri
- GPS özellikli cihaz önerilir (gerçek konum için)
- iPhone 12 ve üzeri modeller için optimize edilmiş
- iPhone 16 Pro'da en iyi performans

## 🔄 Güncelleme Notları

### v1.0.0 (İlk Sürüm)
- ✅ Uydu haritası
- ✅ Gerçek zamanlı drone takibi
- ✅ Uçuş yolu görselleştirmesi
- ✅ Telemetri overlay paneli
- ✅ Center on Drone özelliği
- ✅ Clear Path özelliği
- ✅ iPhone 16 Pro optimizasyonu

---

## 💡 İpuçları

1. **GPS Fix**: En az 5 uydu beklemelisiniz kaliteli takip için
2. **Battery**: Voltaj renkli gösterge sayesinde batarya durumunu kolayca görebilirsiniz
3. **Performance**: 1000'den fazla nokta eklenmez, otomatik temizlenir
4. **Zoom**: Parmak hareketleriyle zoom yapabilirsiniz
5. **Pan**: Haritayı kaydırabilirsiniz, Center butonuyla drone'a geri dönebilirsiniz

Başarılar! 🚁✨
