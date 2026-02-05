# Yakala Project - Coding Conventions

## 🏗 Mimari ve State Management
- **State Management:** `Provider` paketi kullanılacaktır. Basit durumlar için `ChangeNotifier` yeterlidir. Karmaşık iş mantığını UI'dan ayırın.
- **Klasör Yapısı:**
  - `lib/pages/`: Ekranlar ve sayfalar.
  - `lib/utils/`: Yardımcı fonksiyonlar ve araçlar.
  - `lib/widgets/`: Yeniden kullanılabilir UI bileşenleri.
  - `lib/models/`: Veri modelleri.
  - `lib/services/`: Dış servisler veya native API çağrıları.

## 🎨 UI/UX Standartları
- **Material Design:** Flutter'ın güncel Material 3 standartlarını takip et.
- **Responsive:** Masaüstü pencere boyutlandırmalarına duyarlı olmalı.
- **Gap:** Boşluklar için `SizedBox` yerine `gap` paketini kullan.

## 💻 Kod Standartları (Dart/Flutter)
- **Strict Typing:** `dynamic` kullanımından kaçın. Tipleri açıkça belirt.
- **Linter:** `flutter_lints` kurallarına uy. `const` kullanımına dikkat et.
- **Async/Await:** `.then` zincirleri yerine `async/await` yapısını tercih et.
- **İsimlendirme:**
  - Dosyalar: `snake_case` (örn. `user_profile.dart`)
  - Sınıflar: `PascalCase` (örn. `UserProfile`)
  - Değişkenler: `camelCase` (örn. `userName`)

## 🔌 Desktop Eklentileri
- `window_manager`, `system_tray`, `hotkey_manager` gibi native özellikler kullanılırken platform kontrolleri (örn. `Platform.isMacOS`) yapmayı unutma.
- Native kaynakları (listener'lar, stream'ler) `dispose` metodunda mutlaka temizle.
