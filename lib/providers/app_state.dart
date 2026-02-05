import 'package:flutter/material.dart';

enum AppPage { home, capture, settings }

class AppState extends ChangeNotifier {
  AppPage _currentPage = AppPage.home;
  
  // Settings State (Basitlik için burada tutuyoruz, ileride ayrılabilir)
  bool _startAtLogin = false;
  bool _soundEffect = true;
  String _savePath = "~/Documents/Yakala";

  AppPage get currentPage => _currentPage;
  bool get startAtLogin => _startAtLogin;
  bool get soundEffect => _soundEffect;
  String get savePath => _savePath;

  void navigateTo(AppPage page) {
    if (_currentPage != page) {
      _currentPage = page;
      notifyListeners();
    }
  }

  void toggleStartAtLogin(bool value) {
    _startAtLogin = value;
    notifyListeners();
    // TODO: Burada native entegrasyon yapılacak (launchctl vs.)
  }

  void toggleSoundEffect(bool value) {
    _soundEffect = value;
    notifyListeners();
  }

  void updateSavePath(String path) {
    _savePath = path;
    notifyListeners();
  }
}
