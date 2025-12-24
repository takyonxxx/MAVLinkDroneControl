#!/bin/bash

# MobileVLCKit Installation Script
# This script downloads and installs MobileVLCKit for your DroneControl project

set -e  # Exit on error

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  MobileVLCKit Installation Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if we're in the right directory
if [ ! -f "DroneControl.xcodeproj/project.pbxproj" ]; then
    echo "❌ Hata: DroneControl.xcodeproj bulunamadı!"
    echo "Lütfen bu scripti proje klasöründe çalıştırın."
    exit 1
fi

echo "✅ Proje klasörü bulundu"
echo ""

# Create Frameworks directory
mkdir -p Frameworks
echo "📁 Frameworks klasörü oluşturuldu"
echo ""

# Method 1: Check if MobileVLCKit already exists in Pods
if [ -d "Pods/MobileVLCKit/MobileVLCKit.xcframework" ]; then
    echo "✅ MobileVLCKit Pods klasöründe bulundu!"
    echo "📋 Framework kopyalanıyor..."
    cp -R Pods/MobileVLCKit/MobileVLCKit.xcframework Frameworks/
    
    if [ -d "Frameworks/MobileVLCKit.xcframework" ]; then
        echo "✅ Framework başarıyla kopyalandı!"
        echo ""
        echo "🧹 CocoaPods temizleniyor..."
        pod deintegrate 2>/dev/null || true
        rm -rf Pods/ Podfile Podfile.lock DroneControl.xcworkspace
        echo "✅ Temizleme tamamlandı!"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✅ BAŞARILI! Framework hazır."
        echo ""
        echo "Şimdi şunları yapın:"
        echo "1. Xcode'da DroneControl.xcodeproj dosyasını açın"
        echo "2. Frameworks/MobileVLCKit.xcframework dosyasını"
        echo "   proje navigatörüne sürükleyin"
        echo "3. 'Copy items if needed' seçeneğini işaretleyin"
        echo "4. Target → General → Frameworks, Libraries, and Embedded Content"
        echo "5. MobileVLCKit.xcframework → 'Embed & Sign' seçin"
        echo "6. Product → Clean Build Folder (Cmd+Shift+K)"
        echo "7. Product → Build (Cmd+B)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
    fi
fi

# Method 2: Download via CocoaPods
echo "📥 MobileVLCKit indiriliyor..."
echo ""
echo "Bu işlem birkaç dakika sürebilir (framework ~150MB)..."
echo ""

# Create Podfile if it doesn't exist
cat > Podfile << 'EOF'
platform :ios, '18.0'

target 'DroneControl' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.6.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
    end
  end
end
EOF

echo "📝 Podfile oluşturuldu"
echo ""

# Run pod install
echo "⬇️  Pod install çalıştırılıyor..."
pod install --verbose

# Check if download was successful
if [ -d "Pods/MobileVLCKit/MobileVLCKit.xcframework" ]; then
    echo ""
    echo "✅ İndirme başarılı!"
    echo "📋 Framework kopyalanıyor..."
    cp -R Pods/MobileVLCKit/MobileVLCKit.xcframework Frameworks/
    
    if [ -d "Frameworks/MobileVLCKit.xcframework" ]; then
        echo "✅ Framework başarıyla kopyalandı!"
        echo ""
        echo "🧹 CocoaPods temizleniyor..."
        pod deintegrate
        rm -rf Pods/ Podfile Podfile.lock DroneControl.xcworkspace
        echo "✅ Temizleme tamamlandı!"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✅ BAŞARILI! Framework hazır."
        echo ""
        echo "Framework konumu:"
        ls -lh Frameworks/MobileVLCKit.xcframework
        echo ""
        echo "Şimdi şunları yapın:"
        echo "1. Xcode'da DroneControl.xcodeproj dosyasını açın"
        echo "2. Frameworks/MobileVLCKit.xcframework dosyasını"
        echo "   proje navigatörüne sürükleyin"
        echo "3. 'Copy items if needed' seçeneğini işaretleyin"
        echo "4. Target → General → Frameworks, Libraries, and Embedded Content"
        echo "5. MobileVLCKit.xcframework → 'Embed & Sign' seçin"
        echo "6. Product → Clean Build Folder (Cmd+Shift+K)"
        echo "7. Product → Build (Cmd+B)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
    else
        echo "❌ Framework kopyalama başarısız!"
        exit 1
    fi
else
    echo ""
    echo "❌ Pod install başarısız oldu"
    echo ""
    echo "Pods klasör içeriği:"
    ls -la Pods/ 2>/dev/null || echo "Pods klasörü boş"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  Alternatif Çözüm: Swift Package Manager"
    echo ""
    echo "CocoaPods başarısız oldu. SPM kullanmanızı öneriyorum:"
    echo ""
    echo "1. Xcode'da DroneControl.xcodeproj dosyasını açın"
    echo "2. File → Add Package Dependencies..."
    echo "3. Bu URL'i girin:"
    echo "   https://github.com/nnsnodnb/vlckit-spm"
    echo "4. Dependency Rule: 'Up to Next Major Version' - 3.6.0"
    echo "5. Add Package → MobileVLCKit seçin → Add Package"
    echo "6. Product → Build"
    echo ""
    echo "Bu yöntem sandbox hataları vermez!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi
