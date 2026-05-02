# Yakala — Business Flow Documentation

Bu doküman uygulamanın tüm kullanıcı akışlarını, state geçişlerini, klavye/mouse etkileşimlerini, edge case'lerini ve servis koordinasyonunu **en ince ayrıntısına kadar** belgeler. Geliştirici buradan ne kullanıcının ne göreceğini, ne arka planda ne olacağını eksiksiz öğrenebilir.

---

## 1. Yüksek Seviye Felsefe

Yakala bir **tray-only** uygulamadır. Normal kullanımda **hiçbir pencere görünmez**. Pencere yalnızca iki durumda açılır:
1. Tray'den **Ayarlar** seçildiğinde (settings penceresi)
2. **Region capture** sırasında geçici olarak (fullscreen overlay)

`fullScreen` ve `window` modları için pencere açılmaz; doğrudan native capture → opsiyonel editor → clipboard.

Tüm yakalamalar şu ortak son adımdan geçer (`_finalize`):
1. Clipboard'a kopyala
2. (Eğer `savePath` set ise) diske yaz
3. (Eğer `soundEffect` açık ise) deklanşör sesi
4. (Eğer `notificationsEnabled` açık ise) native bildirim

---

## 2. Uygulama Yaşam Döngüsü

### 2.1 Başlatma (`main.dart`)

Sırayla:

1. **`SingleInstanceService.acquire()`**
   - `<temp>/yakala.lock` dosyası okunur
   - İçinde canlı PID varsa → `exit(0)` (ikinci örnek sessizce çıkar)
   - Stale lock varsa (PID ölü) → devral
   - Atomic: önce `<temp>/yakala.lock.<pid>.tmp` yazılır, sonra `rename()` ile final ada alınır (POSIX'te atomik)

2. **`TempCleanup.sweepOld()`** (fire-and-forget — `await` edilmez)
   - 24 saatten eski `yakala*.png` dosyaları silinir
   - Lock dosyasına dokunulmaz
   - Hata olursa sessiz geç (best effort)

3. **`WindowService.initialize()`**
   - `windowManager.ensureInitialized()`
   - `WindowOptions(size: 560×640, hidden, transparent, no titlebar, skipTaskbar)`
   - `setPreventClose(true)` — X butonu kapatmasın, sadece gizlesin
   - `WindowListener` bağlanır
   - Pencere `hide()` ile başlar (kullanıcıya görünmez)

4. **`AutostartService.initialize()`**
   - `kReleaseMode` değilse hiçbir şey yapmaz (dev'de Dart binary'ye autostart eklenmesin)
   - Release'de `PackageInfo` ile bundle adı/path'i okunur, `launchAtStartup.setup()` çağrılır

5. **`SettingsProvider.create(autostart)`**
   - `SharedPreferences.getInstance()`
   - Mevcut değerler okunur (yoksa default'lar)
   - `AutostartService` reference'ı tutulur (toggle değişince çağrılacak)

6. **`RegionSelectorService` ve `AnnotationService`** instantiate edilir
   - İkisi de `OverlayController<TResult, TPayload>` extend eder
   - `start(payload) → Future<result?>` API'si

7. **`CaptureService`** üç servis (settings, regionSelector, annotation, windowService) ile inşa edilir

8. **`HotkeyService.register(settings.hotkey, callback)`**
   - Önceki HotKey varsa unregister edilir (sadece kendininki)
   - `hotKeyManager.register()` çağrılır
   - Başarılıysa `true`, OS başka uygulamaya tahsis ettiyse `false`
   - Callback: `captureService.capture(settings.defaultCaptureMode)`
   - `false` dönerse log uyarısı (toast yok — main'de UI mevcut değil)

9. **`TrayService.initialize(hotkeyLabel, ...)`**
   - Tray icon oluşturulur (`assets/app_icon.png` → tempfile)
   - Tooltip: `'Yakala — ⌘ ⇧ C'` (mevcut hotkey label'ı)
   - Menu yapısı:
     ```
     Ekranı Yakala ▶
       Tüm Ekran
       Bölge Seç
       Pencere
     ─────
     Ayarlar
     ─────
     Çıkış
     ```

10. **Settings change listener** kayıt edilir
    - `settings.hotkey` değişince `trayService.updateTooltip(newLabel)`
    - `notifyListeners` her settings değişiminde tetiklenir; en azından gereksiz tray API çağrısı oluyor — kabul edilen küçük cost

11. **`runApp()`**
    - `MultiProvider`: SettingsProvider, RegionSelectorService, AnnotationService, **WindowService**
    - Root: `Consumer3<RegionSelectorService, AnnotationService, WindowService>`
      - `annotation.isActive` → `AnnotationEditor` (full-screen mode için)
      - `region.isActive` → `RegionOverlay` (region mode için)
      - `windowService.settingsVisible` → `SettingsPage`
      - Aksi halde → `ColoredBox(transparent)` (görünmez placeholder)
    - **Önemli:** SettingsPage **fallback değil**, yalnız `settingsVisible == true` ise render edilir. Bu sayede capture confirm sonrası overlay kapanırken bir frame için fullscreen settings görünmez.

### 2.2 Çıkış (Tray → "Çıkış")

Sırayla:
1. `hotkeyService.dispose()` — kayıtlı hotkey'i unregister et
2. `trayService.dispose()` — tray icon'u kaldır
3. `windowService.dispose()` — WindowListener'ı çıkar
4. `lock.release()` — lock dosyasını sil (sahip olduğumuzu kontrol ederek)
5. `exit(0)`

**Önemli:** Lock release'i sadece bizim PID'miz lock'ta kayıtlı ise siler. Başka örnek devraldıysa korunur.

### 2.3 Pencere Kapatma (X Butonu)

`WindowListener.onWindowClose` çağrılır:
- Eğer overlay modundaysa: `exitOverlay()` (hide → resize → settings size)
- Aksi halde: `hide()` (uygulama tray'de çalışmaya devam eder)

`setPreventClose(true)` sayesinde gerçek kapatma engellenir.

### 2.4 WindowService Visibility State Machine

`WindowService` artık `ChangeNotifier`. Üç state flag tutar:
- `_inOverlayMode` — region/editor aktif
- `_settingsVisible` — kullanıcı kasıtlı olarak Settings'i açtı

| Event | `_inOverlayMode` | `_settingsVisible` | Pencere |
|---|---|---|---|
| `initialize()` | false | false | Hidden |
| `showSettings()` | false (exitOverlay if was true) | **true** | Visible, normal size |
| `hide()` | unchanged | **false** | Hidden |
| `enterOverlay(size)` | **true** | **false** | Visible, fullscreen |
| `exitOverlay()` | **false** | unchanged | Hidden, resize edilir |
| `onWindowClose()` (X) | overlay ise exitOverlay, değilse hide | depends | Hidden |

`notifyListeners()` her state değişiminde tetiklenir → root Consumer rebuild eder. **Önemli:** `exitOverlay` önce `windowManager.hide()` çağırır, sonra `_inOverlayMode = false` + `notifyListeners()`. Bu sayede widget tree fallback widget'a (ColoredBox) geçtiği anda pencere zaten gizli — flash olmaz.

---

## 3. Settings Penceresi

### 3.1 Açılış Yolları
- Tray menü → "Ayarlar"
- (Yok) Hotkey bunu açmaz; capture tetikler

### 3.2 İçerik

#### GENEL Bölümü (4 toggle)
| Toggle | Default | Side Effect |
|---|---|---|
| Başlangıçta Çalıştır | false | `AutostartService.setEnabled()`. Dev modda **disabled** ve subtitle "Sadece release build'de aktif" |
| Bildirimler | true | Sadece flag, capture finalize'da okunur |
| Ses Efekti | true | Sadece flag |
| Yakalama Sonrası Düzenle | true | Sadece flag |

#### VARSAYILAN MOD
- `SegmentedButton<CaptureMode>`: Tüm Ekran / Bölge Seç / Pencere
- Hotkey'in tetiklediği mode bu

#### KISAYOL
- Mevcut kombinasyon gösterilir (örn `⌘ ⇧ C`)
- Tıklanca recording moduna girer, kullanıcı kombinasyon basar
- En az 1 modifier zorunlu (sadece harfe izin yok); aksi halde "En az bir modifier (⌘/⇧/⌥/⌃) gerekli" hint
- Esc → iptal
- Yeni kombinasyon yakalanınca:
  1. `settings.setHotkey(config)` — persist
  2. `hotkeyService.update(config)` — aktif hotkey değiştir
  3. Eğer `update` `false` dönerse → SnackBar uyarısı: "Kısayol kaydı başarısız: muhtemelen başka uygulama kullanıyor."
  4. `settings.notifyListeners` → tray tooltip güncellenir

#### KAYIT YERİ
- Boşsa: "Sadece pano (disk kaydı yok)"
- Doluysa: tam path gösterilir (long → ellipsis)
- "Değiştir" → `getDirectoryPath()` (file_selector) → kullanıcı klasör seçer
- "Temizle" (X) → `setSavePath('')`

### 3.3 Kapatma
- Sol üst X → `windowService.hide()` (app çalışmaya devam eder)
- Sistem X → aynı (prevent-close)

---

## 4. Capture Akışı — Genel

### 4.1 Tetikleme Yolları

**Hotkey** (her platformda global, default `⌘⇧C`):
```
keyDownHandler → captureService.capture(settings.defaultCaptureMode)
```

**Tray menü** → "Ekranı Yakala" → submenu:
- "Tüm Ekran" → `capture(CaptureMode.fullScreen)`
- "Bölge Seç" → `capture(CaptureMode.region)`
- "Pencere" → `capture(CaptureMode.window)`

### 4.2 Permission Check (her capture başında)

`_ensurePermission()`:
- macOS: `screenCapturer.isAccessAllowed()`
  - `false` → `requestAccess()` (System Settings'i açar) + bildirim "Ekran kaydı izni gerekiyor..." + `failed('izin yok')` döner
  - `true` → devam
- Linux/Windows: her zaman `true` (paket-level kontrol yok)

### 4.3 Mode Yönlendirmesi

```dart
if (mode == CaptureMode.region) → _selectRegion (in-place editor)
else                            → _captureNative (+ opsiyonel full-screen editor)
```

---

## 5. Region Capture (En Karmaşık Akış)

### 5.1 Adım Adım

```
[1] User triggers (hotkey/tray)
[2] windowService.hide() — settings görünüyorsa kapat
[3] await 80ms — pencere efektif kaybolsun
[4] SilentCapture.captureFullScreen(tempPath)
    Linux:  grim (Wayland) → import (X11) → scrot → maim
    macOS:  screencapture -x -t png
    Windows: PowerShell .NET Bitmap.CopyFromScreen
    8s timeout her bir komuta. Tümü başarısız → screen_capturer fallback (silent: true)
[5] screenRetriever.getPrimaryDisplay() → logical size + scaleFactor
[6] windowService.enterOverlay(logicalSize)
    - setAlwaysOnTop(true), setResizable(false), setMovable(false-yalnız macOS)
    - setSize(logicalSize), setPosition(0,0)
    - show(), focus()
    - Her çağrı _safe() ile sarılı (Linux'ta setMovable yok → hata yutuluyor)
[7] regionSelector.startWith(image, logicalSize)
    - Completer<Uint8List?> oluşturulur
    - notifyListeners → root Consumer rebuild → RegionOverlay render edilir
[8] [User interacts with RegionOverlay - bkz §5.2]
[9] Completer resolves with: annotated bytes / null
[10] windowService.exitOverlay()
    - hide(), setAlwaysOnTop(false), setResizable(true), settings size, center
[11] SilentCapture geçici dosyası silinir
[12] Bytes yeni temp PNG'ye yazılır → _finalize
```

### 5.2 RegionOverlay — İki Fazlı UI

#### Phase 1: SELECTING (başlangıç durumu)

**Görünen:**
- Frozen background screenshot (full-screen)
- %45 dim overlay
- Hint bar (alt orta): `"Sürükle: bölge seç (bırakınca düzenleme açılır)   •   Köşe/kenar: yeniden boyutlandır   •   Esc: iptal"`

**State:**
- `_phase = _Phase.selecting`
- `_selection: Rect? = null` (henüz çizim yok)
- `_mode: _DragMode = .idle`
- `_currentCursor: SystemMouseCursors.precise`

**Mouse:**
| Hareket | Davranış |
|---|---|
| Hover (genel) | Cursor `precise` |
| Pan başlat (selection yokken) | `_mode = .drawing`, `_drawAnchor = pos`, selection ufak rect olarak oluşturulur |
| Pan başlat (selection üstünde, handle'a yakın) | `_mode = .resizing`, `_activeHandle = X` |
| Pan başlat (selection içinde, handle'sız) | `_mode = .moving`, `_moveOffset` hesaplanır |
| Pan update | `_mode`'a göre `_selection` güncellenir; ekran sınırlarına `clamp` |
| Pan end (drawing & sel < 5×5) | `_selection = null`, mode → idle |
| **Pan end (drawing & sel ≥ 5×5)** | **`_confirmSelection()` çağrılır → annotating phase'e geçer** |
| Pan end (resizing/moving) | mode → idle, kalır selecting'de |

**Klavye:**
| Tuş | Davranış |
|---|---|
| Esc | `widget.onCancel()` → `regionSelector.cancel()` → null result |
| Enter / Cmd+C / Ctrl+C | `_confirmSelection()` (manuel transition de mümkün) |

**Cursor değişimi:** `_updateCursor(pos)` her hover'da çağrılır ama `setState` yalnız cursor _gerçekten_ değiştiyse — perf optimize.

**Handle hit-test:**
- 8 handle: 4 köşe + 4 kenar orta
- `_handleSize = 10px`, hit padding `+8px` → 26×26 efektif tıklanabilir alan
- Köşeden başlayıp test edilir; ilk eşleşen kazanır

**Resize matematiği:**
- `_resize(rect, handle, pos)` — handle'a göre rect'in ilgili köşesi/kenarı `pos`'a snap
- Sonra `_normalize(rect)` — negatif width/height olmaz (drag karşı tarafa geçerse rect ters çevrilir)

**Move matematiği:**
- `newTL = pos - _moveOffset` (drag başlangıçtaki offset korunur)
- `clamp(0, screenSize - selectionSize)` — selection ekran dışına kaymaz

#### Phase Transition: selecting → annotating

`_confirmSelection()`:
1. Selection valid mi? (>5×5) — değilse no-op
2. `_cropBackground(sel, logicalSize)` — `image.decodePng → copyCrop → encodePng`
3. Yeni `ImagePainterController` oluştur (color: red, stroke: 4, mode: freeStyle)
4. setState: `_phase = annotating`, `_croppedBytes = ...`, `_annotCtrl = ctrl`

Crop async olduğu için ~50-200ms gecikme olabilir. Bu süre boyunca user ne görür: hala selecting phase widget'ları (selection rect + handles görünüyor; sonra setState ile annotating render edilir).

#### Phase 2: ANNOTATING

**Görünen:**
- Aynı frozen background
- Aynı %45 dim (selection rect dışı)
- Selection rect içinde: `ImagePainter.memory(_croppedBytes, controller: _annotCtrl, showControls: false, scalable: false)` — **handle yok**
- Selection rect kenarına: 1px beyaz border
- Floating toolbar — selection'ın hemen altında (ekrana sığmazsa üstünde, ikisi de sığmazsa ekran altına 20px margin)

**Toolbar Içeriği:**
```
[Pen] [Çizgi] [Ok] [Dikdörtgen] [Daire] [Yazı]  |  [8 renk swatch]  |  [Stroke slider 1-20]  |  [Undo] [Clear]  |  [Crop=geri-seçim] [X=iptal] [✓ Bitti]
```

- Tool butonları: aktif olan seçili (primary tint background)
- Renk swatch: 8 renk (red, orange, yellow, green, blue, purple, white, black). Aktif olan beyaz ring ile vurgulu
- Stroke slider: 1-20 arası, custom theme (beyaz track + thumb)
- Undo: controller.undo()
- Clear: controller.clear() — **tüm annotation'ları siler, geri alma yok**
- Crop icon: `_backToSelecting()` → phase 1'e döner, selection korunur, handles tekrar görünür
- X icon: `widget.onCancel()` → tüm akış iptal
- Bitti: `_confirmAnnotation()`

**State:**
- `_phase = annotating`
- `_selection` korunur (görsel için)
- `_croppedBytes` yeni cropped PNG
- `_annotCtrl` `ImagePainterController` instance

**Mouse:**
- Selection içinde: ImagePainter hit-test alır → seçili moda göre çizim yapar
- Selection dışında: hiçbir gesture aktif değil (Phase 1 GestureDetector render edilmiyor)
- ImagePainter scalable: false — kullanıcı zoom yapamaz (tasarım kararı; zoom gereksiz çünkü selection zaten kullanıcının istediği boyutta)

**Klavye:**
| Tuş | Davranış |
|---|---|
| Esc | `_backToSelecting()` — toolbar kaybolur, handles geri gelir |
| Enter / Cmd+C / Ctrl+C | `_confirmAnnotation()` |
| Cmd+Z / Ctrl+Z | `_annotCtrl.undo()` |

**Yazı (text) modu için özel davranış:**
- Tıklayınca image_painter dialog açar, kullanıcı yazı girer
- Bu dialog image_painter'ın internal'ı, müdahale yok

#### `_confirmAnnotation()` — Final

1. `_exporting = true` (UI'da Bitti butonu spinner gösterir)
2. `await _annotCtrl.exportImage()` → `Uint8List?` (annotated PNG)
3. Null dönerse fallback: `_croppedBytes` (kullanıcı çizim yapmamışsa)
4. Hala null → `widget.onCancel()`
5. `widget.onConfirm(bytes)` → `regionSelector.confirm(bytes)` → completer resolve

#### Edge Cases

- **Çok küçük selection (<5×5):** Pan end'te selection silinir, transition tetiklenmez
- **Drag ekran dışına:** Pan update'te `clamp` yapılır
- **Resize negatif boyut:** `_normalize` ile düzeltilir
- **Crop hatası (bozuk PNG):** `_cropBackground` null döner → `widget.onCancel()` (akış iptal)
- **`exportImage` hatası:** Try/catch, null dönerse `_croppedBytes` fallback
- **User Esc'le selecting'e dönüp tekrar drag yaparsa:** Eski selection silinir, yeni drawing başlar, yeni transition

### 5.3 Region Akışı Sonu

`_finalize(annotatedPath, timestamp)`:

1. **Clipboard:** `ClipboardUtils.copyImageToClipboard(path)`
   - Path'te `\n`, `\r`, ` ` varsa **reddedilir** (injection güvenliği)
   - macOS: `osascript` ile `«class PNGf»` (PNG type)
   - Linux: Wayland tespit (`WAYLAND_DISPLAY`), `wl-copy` veya `xclip`
   - Windows: PowerShell `[Clipboard]::SetImage`, path env var üzerinden
   - 8s timeout, exit code kontrol
   - `bool` döner — başarısız da olsa akış devam eder

2. **Disk save (opsiyonel):** `settings.savePath` doluysa
   - `~` expand
   - Klasör yoksa `create(recursive: true)`
   - `File.copy` ile

3. **Sound (opsiyonel):** `settings.soundEffect`
   - `unawaited(SoundService.playCaptureSound())`
   - 800ms cooldown — accidental double-trigger'a karşı
   - Detached process — audio kuyruğunda hang olsa bile app etkilenmez

4. **Notification (opsiyonel):** `settings.notificationsEnabled`
   - Body içeriği clipboardOk + savedToDisk durumuna göre dinamik:
     - "Görüntü panoya kopyalandı." (clipboard ok)
     - "Panoya kopyalandı ve diske kaydedildi." (her ikisi)
     - "Diske kaydedildi: yakala_xxx.png" (clipboard fail)
     - "Yakalandı ama kaydedilemedi." (her ikisi fail)

---

## 6. Full Screen / Window Mode Akışı

### 6.1 Adım Adım

```
[1] User triggers (hotkey/tray)
[2] _ensurePermission() — macOS gate
[3] sc.screenCapturer.capture(mode: screen|window, silent: true)
    silent: true her zaman — bizim kendi sound'umuzu finalize'da çalıyoruz
    Window mode: macOS native window picker, Linux gnome-screenshot --window
[4] capturedData null veya dosya yok → CaptureResult.cancelled()
[5] Eğer settings.showEditorAfterCapture true:
    [5a] _runEditor(path, timestamp)
         - screenRetriever ile logical size al
         - windowService.enterOverlay(size)
         - annotationService.start(bytes) → AnnotationEditor render edilir
         - User confirm/cancel sonucu await edilir
         - Confirm: yeni temp PNG'ye yaz, eski capture'ı sil
         - Cancel: capture sil, null dön → CaptureResult.cancelled()
[6] _finalize(path, timestamp) — bkz §5.3
[7] finally: inOverlay ise windowService.exitOverlay()
```

### 6.2 AnnotationEditor (Full-screen Editor)

Bu region overlay'den FARKLI bir widget. Region'ın in-place toolbar'ı yerine **klasik full-screen editor** kullanır:
- Üstte siyah action bar: [X İptal] | "Düzenle" | [✓ Bitti]
- Ortada `ImagePainter.memory(showControls: true)` — paket built-in toolbar (İngilizce — paket limitasyonu)
- Resim tüm ekranı kaplar, padding 16px

**State:**
- `_controller: ImagePainterController` (initState'de oluşturulur)
- `_exporting: bool` — Bitti spinner

**Dispose:**
- Controller manuel dispose **edilmez** — image_painter widget kendisi dispose eder. (v0.7.1 sürüm spesifik davranış; double-dispose crash'i yaşandı, fix uygulandı)

**Klavye:** Aktif key handler yok — kullanıcı butonlara tıklar

---

## 7. State Diyagramı

```
                ┌──────────────────────────────┐
                │ App start                    │
                │ - Lock acquired              │
                │ - Window hidden              │
                │ - Tray visible               │
                └──────────────┬───────────────┘
                               │
                  ┌────────────┴────────────┐
                  │                         │
              [Tray "Ayarlar"]    [Hotkey/Tray "Yakala"]
                  │                         │
                  ▼                         ▼
        ┌─────────────────┐    ┌─────────────────────────────┐
        │ Settings shown  │    │ permission check (macOS)    │
        │ Window normal   │    └────────────┬────────────────┘
        └────────┬────────┘                 │
                 │                          ▼
            [X / Esc]              ┌────────┴─────────┐
                 │                 │                  │
                 ▼              [region]      [fullScreen/window]
        ┌────────────────┐         │                  │
        │ Window hidden  │         ▼                  ▼
        │ Tray only      │  ┌─────────────┐  ┌────────────────┐
        └────────────────┘  │ silent      │  │ screenCapturer │
                            │ full-screen │  │ silent: true   │
                            │ capture     │  └───────┬────────┘
                            └──────┬──────┘          │
                                   │                 │
                                   ▼                 ▼
                            ┌──────────────┐  ┌─────────────────┐
                            │ enterOverlay │  │ if showEditor:  │
                            └──────┬───────┘  │   enterOverlay  │
                                   ▼          │   AnnotationEd. │
                            ┌──────────────┐  └────────┬────────┘
                            │ RegionOverlay│           │
                            │ Phase 1      │           │
                            │ "selecting"  │           │
                            └──────┬───────┘           │
                              [drag end]               │
                                   │                   │
                                   ▼                   │
                            ┌──────────────┐           │
                            │ RegionOverlay│           │
                            │ Phase 2      │           │
                            │ "annotating" │           │
                            │ ←── [Esc] ───┤           │
                            └──────┬───────┘           │
                              [Bitti/Ctrl+C]           │
                                   │                   │
                                   ▼                   ▼
                            ┌──────────────────────────┐
                            │ exitOverlay              │
                            │ _finalize:               │
                            │   - clipboard            │
                            │   - disk (opt)           │
                            │   - sound (opt)          │
                            │   - notification (opt)   │
                            └──────────────────────────┘
```

---

## 8. Klavye Kısayolları (Tam Liste)

### Global (Sistem Genelinde)
| Kombinasyon | Eylem |
|---|---|
| `⌘⇧C` (default, customize edilebilir) | `defaultCaptureMode` ile yakalama |

### Settings → Hotkey Recorder
| Tuş | Eylem |
|---|---|
| Herhangi bir kombinasyon (modifier + tuş) | Yakalanır, `setHotkey` çağrılır |
| `Esc` | Recording iptal |

### Region Overlay — Phase 1 (selecting)
| Tuş | Eylem |
|---|---|
| `Esc` | Tüm akışı iptal |
| `Enter` / `Cmd+C` / `Ctrl+C` | Manuel olarak annotating'e geç (auto-transition zaten var ama backup) |

### Region Overlay — Phase 2 (annotating)
| Tuş | Eylem |
|---|---|
| `Esc` | Phase 1'e dön (selection korunur) |
| `Enter` / `Cmd+C` / `Ctrl+C` | Annotation'ı flatten et + clipboard'a |
| `Cmd+Z` / `Ctrl+Z` | Undo |

### AnnotationEditor (Full-screen, fullScreen/window mode için)
- Klavye handler yok; kullanıcı X / Bitti butonlarına tıklar

---

## 9. Service Coordination Matrix

| Olay | Hangi servisler etkilenir |
|---|---|
| Hotkey trigger | HotkeyService → CaptureService → SilentCapture/screen_capturer → RegionSelector/Annotation → ClipboardUtils → SoundService → NotificationService |
| Tray menu click | TrayService → CaptureService veya WindowService |
| Settings hotkey değişti | SettingsProvider → HotkeyService.update + TrayService.updateTooltip |
| Settings autostart toggle | SettingsProvider → AutostartService |
| Window X butonu | WindowService.onWindowClose → hide |
| App quit | HotkeyService.dispose → TrayService.dispose → WindowService.dispose → lock.release |

---

## 10. Persistence (SharedPreferences Anahtarları)

| Key | Type | Default | Anlamı |
|---|---|---|---|
| `start_at_login` | bool | false | Autostart toggle |
| `sound_effect` | bool | true | Capture sound aktif |
| `notifications_enabled` | bool | true | Native notification aktif |
| `show_editor_after_capture` | bool | true | Yakalama sonrası editor |
| `save_path` | string | "" | Disk save klasörü ("" = sadece pano) |
| `hotkey_config` | string (JSON) | `{key: 0x70006, modifiers: ["meta","shift"]}` | Global hotkey |
| `default_capture_mode` | int | 0 (fullScreen) | Hotkey'in tetiklediği mode |

**Forward compatibility:** `hotkey_config.modifiers` JSON string olarak yazılır (eski formatta int index'ti — geriye uyumlu okuma var).

---

## 11. Temp File Yaşam Döngüsü

| Dosya | Ne zaman oluşur | Ne zaman silinir |
|---|---|---|
| `<tmp>/yakala.lock` | App start | App quit (sahibi ise) |
| `<tmp>/yakala.lock.<pid>.tmp` | acquire() içinde | Hemen rename veya delete |
| `<tmp>/yakala_full_<ts>.png` | Region: silent capture sonrası | Region selection bittiğinde (confirm/cancel) |
| `<tmp>/yakala_<ts>.png` | Final output (region veya native) | 24+ saat sonra TempCleanup tarafından |
| `<tmp>/yakala_edit_<ts>.png` | Full-screen editor onayında | 24+ saat sonra TempCleanup tarafından |
| `<tmp>/app_icon.png` | TrayUtils.getIconPath ilk çağrıda | OS temp temizliğine bırakılır |

**TempCleanup pattern:** `^yakala(_full|_edit)?_\d+\.png$` regex ile match edilen + 24h+ eski dosyalar startup'ta silinir. Lock dosyası matchlemediği için dokunulmaz.

---

## 12. Güvenlik Sınırları

### Shell Injection Vektörleri
Tüm `Process.run` / `Process.start` çağrıları aşağıdaki kuralları uygular:

1. **Path validation:** `\n`, `\r`, ` ` (space) içeren path'ler reddedilir (clipboard, silent capture)
2. **Newline reject:** Notification body'sinde `\n` → space replace
3. **Windows env-var passing:** PowerShell script'leri **kullanıcı string'lerini interpolate etmez**, env var üzerinden geçer (`environment: {'YAKALA_X': value}`)
4. **Timeouts:** 4-8s (komuta göre) — hung process app'i hang etmez

### Process Lifecycle
- `SoundService` — detached mode (parent'tan bağımsız)
- `Clipboard/Notification/SilentCapture` — `Process.run` ile bekler ama timeout var

### Permission Boundaries
- macOS: Screen Recording permission kontrolü her capture'da
- Linux/Windows: OS-level permission kontrolü uygulamada yok (paket bağımlılığı)
- File system: SavePath user-controlled, OS perm checks ile sınırlı

---

## 13. Hata Toleransı

| Senaryo | Davranış |
|---|---|
| Hotkey kayıt başarısız (OS başka uygulamaya tahsis etti) | Settings'te SnackBar + log; capture tetiklenemez |
| Clipboard fail | Notification "Yakalandı ama kaydedilemedi" / disk save varsa "Diske kaydedildi" |
| SilentCapture tüm tool'lar fail | screen_capturer fallback; o da fail → "Tam ekran yakalanamadı" notification |
| screen_capturer fail | "Yakalama başarısız oldu" notification |
| Crop fail | "Bölge işlenemedi" notification (region akışı için) |
| Sound çalmadı | Sessiz, log debug |
| Notification gösterilemedi | Sessiz, log debug |
| Native window service call fail | `_safe()` ile yutulur, log debug |
| Lock dosyası okuma hatası | Acquire `true` döner (kullanıcıyı engellemez) |

---

## 14. Multi-Display Davranışı (Bilinen Sınır)

- `screenRetriever.getPrimaryDisplay()` → her zaman **birincil** ekran
- `SilentCapture` → birincil ekran (Linux import/grim default'ta birincil)
- Region overlay birincil ekranı kaplar
- İkincil monitördeki içerik yakalanmaz; selection ikincil ekrana taşmaz

**Gelecek geliştirme:** `getCursorScreenPoint` ile aktif ekranı tespit edip overlay'i orada açma planlanıyor.

---

## 15. Performans Profili

| İşlem | Tipik Süre | Notlar |
|---|---|---|
| App startup | 500-1500ms | Window init + service registration |
| Hotkey trigger → overlay görünür | 200-400ms | SilentCapture + window resize |
| Selection drag (60fps) | <16ms/frame | DimPainter repaint maliyeti var (4K'de gözle görülür değil) |
| Selection → annotating geçiş | 50-200ms | image.copyCrop main thread (büyük selection'da gözle görülür) |
| Annotation export | 100-500ms | image_painter.exportImage RepaintBoundary üzerinden |
| Clipboard copy | 50-300ms | OS ve dosya boyutuna göre |
| Notification | <100ms | Native, async |
| Sound | <50ms (process spawn) | Detached, audio kuyruğuna bırakılır |

**Bilinen perf zayıflıkları:**
- `image.decodePng` main thread'de (`compute()` ile isolate'a alınabilir)
- `Image.memory` her build'de re-decode ediyor (cache yok)
- `_DimPainter` her selection drag frame'inde repaint (CustomPaint optimize değil)

---

## 16. Test Yapısı

### Unit/Widget Tests (`test/widget_test.dart`)
- `SettingsProvider` default değerler + persistence
- `HotkeyConfig` JSON round-trip
- `SettingsPage` smoke test (Switch sayısı doğru mu)

### Compatibility Tests (`test/platform_compatibility_test.dart`)
- `pubspec.yaml` zorunlu paketler
- `macos/`, `linux/` klasörleri
- `assets/app_icon.png` mevcut
- Backslash path kontrolü

### Mock Channels (`test/helpers/mock_channels.dart`)
Native plugin method channel'ları stub'lanır:
- `window_manager`, `screen_capturer`, `hotkey_manager`, `system_tray`
- `path_provider`, `launch_at_startup`, `package_info_plus`, `screen_retriever`
- `SharedPreferences.setMockInitialValues({})`

### Test Edilmeyen
- `CaptureService` integration (native command çağrıları gerek)
- `RegionOverlay` UI flow (Flutter test ortamı pixel-perfect değil)
- `image_painter` interaction
- `SoundService`, `NotificationService` (process spawn mock'lanmıyor)

---

## 17. Versiyon ve Bilinen Limitasyonlar

### Paket Sürümleri (pubspec.yaml)
- `screen_capturer: ^0.2.3`
- `window_manager: ^0.5.1`
- `hotkey_manager: ^0.2.3`
- `system_tray: ^2.0.3`
- `image_painter: ^0.7.1` — **kritik**: TextDelegate alanları `final`, Türkçe override edilemez

### Linux Sistem Gereksinimleri
```bash
sudo apt install libkeybinder-3.0-dev libayatana-appindicator3-dev \
                 libnotify-bin wl-clipboard xclip imagemagick
```

### Bilinen Çağrı Sırası Edge Case'leri
1. Settings kapatılırken capture tetiklenirse — settings kaybolur (windowService.hide), capture devam eder
2. Capture sırasında ikinci capture tetiklenirse — overlay state çakışır; ikinci `regionSelector.start()` öncekini iptal eder (Completer null ile resolve)
3. App quit sırasında capture devam ediyorsa — `exit(0)` öncesi service dispose, ama capture mid-flight cancel olmuyor; pending Future zaten sonlanır

### Gelecek Geliştirme Listesi
- macOS permission grant sonrası restart prompt (C4)
- Multi-monitor desteği (H3)
- Capture history / preview panel
- OCR / metin çıkarma
- Yakalama seçim hatırlama (son 5 region)
- Cloud upload (Imgur, S3, etc)
- Annotation: blur/pixelate tool, highlight, callouts
- Custom shutter sound seçeneği

---

## Ek: Dosya / Sınıf Index

```
lib/
  main.dart                              — Bootstrap & wiring
  models/
    capture_mode.dart                    — enum (fullScreen | region | window)
    capture_result.dart                  — DTO (success/cancelled/failed)
    hotkey_config.dart                   — Serializable hotkey
  providers/
    settings_provider.dart               — SharedPreferences-backed settings
  services/
    overlay_controller.dart              — Generic OverlayController<R, P>
    region_selector_service.dart         — extends OverlayController
    annotation_service.dart              — extends OverlayController
    capture_service.dart                 — Main orchestrator
    hotkey_service.dart                  — Global hotkey registration
    tray_service.dart                    — System tray + tooltip
    window_service.dart                  — WindowListener + overlay mode
    notification_service.dart            — Native toasts
    sound_service.dart                   — Detached shutter sound
    autostart_service.dart               — launch_at_startup wrapper
    single_instance_service.dart         — Atomic PID lock
  utils/
    clipboard_utils.dart                 — Native clipboard ops (Wayland-aware)
    silent_capture.dart                  — Silent full-screen capture
    temp_cleanup.dart                    — Old PNG sweeping
    tray_utils.dart                      — Asset → tempfile for tray icon
  widgets/
    hotkey_recorder.dart                 — Live hotkey capture UI
    region_overlay.dart                  — Two-phase region UI (selecting + annotating)
    annotation_editor.dart               — Full-screen editor (non-region)
  pages/
    settings_page.dart                   — Settings UI
```
