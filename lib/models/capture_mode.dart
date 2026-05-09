/// UI tarafındaki capture mode enum'u — daemon ile JSON üzerinden enum.name
/// string formatında paylaşılır ("fullScreen", "region", "window").
///
/// Native daemon mimarisinde UI direkt screen_capturer paketini çağırmıyor —
/// capture'ı daemon yapıyor. UI sadece editor/region overlay göstermek için
/// hangi flow'da olduğunu bilmesi gerek (fullScreen yakalama sonrası direkt
/// editor; region yakalama sonrası önce overlay sonra editor).
enum CaptureMode {
  fullScreen,
  region,
  window;

  String get label {
    switch (this) {
      case CaptureMode.fullScreen:
        return 'Tüm Ekran';
      case CaptureMode.region:
        return 'Bölge Seç';
      case CaptureMode.window:
        return 'Pencere';
    }
  }
}
