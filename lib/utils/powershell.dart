import 'dart:io';

/// Tüm Windows PowerShell çağrıları için tek nokta.
///
/// Standart bayraklar:
///   -NoProfile             : profile script'lerini atla → hızlı, deterministik
///   -NonInteractive        : prompt çıkmasını engelle (çağrı asılı kalmasın)
///   -ExecutionPolicy Bypass: kurumsal makinelerde policy `Restricted` /
///                            `AllSigned` olabilir; biz inline -Command ile
///                            çalıştırdığımız için disk script imzasız.
///                            Bypass tek seferlik bu süreç içindir, registry'ye
///                            yazmaz.
///
/// Tüm kullanıcı girdileri çağrı argümanlarında değil, `environment` üzerinden
/// `$env:VAR` ile geçirilmelidir → PowerShell argument parser'da quoting
/// sorunu yaratmaz, command injection imkansız.
class PowerShell {
  static const _baseFlags = [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
  ];

  static Future<ProcessResult> run({
    required String script,
    required Duration timeout,
    Map<String, String>? environment,
  }) {
    return Process.run(
      'powershell',
      [..._baseFlags, script],
      environment: environment,
    ).timeout(timeout);
  }

  static Future<Process> startDetached({
    required String script,
    Map<String, String>? environment,
  }) {
    return Process.start(
      'powershell',
      [..._baseFlags, script],
      mode: ProcessStartMode.detached,
      environment: environment,
    );
  }
}
