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

  /// `powershell` çağrısının argüman listesi. Test seam: dependency injection
  /// olmadan da PowerShell.run/startDetached'in kullanacağı argümanların
  /// doğru sırada olduğunu unit test'ten doğrulayabilelim diye public.
  ///
  /// Sıralama önemli: `-Command` MUTLAKA en sonda olmalı, ondan sonra ilk
  /// argüman script gövdesi olarak parse edilir. Araya başka flag girerse
  /// PowerShell script'i flag sanır.
  static List<String> buildArgs(String script) {
    return [..._baseFlags, script];
  }

  static Future<ProcessResult> run({
    required String script,
    required Duration timeout,
    Map<String, String>? environment,
  }) {
    return Process.run(
      'powershell',
      buildArgs(script),
      environment: environment,
    ).timeout(timeout);
  }

  static Future<Process> startDetached({
    required String script,
    Map<String, String>? environment,
  }) {
    return Process.start(
      'powershell',
      buildArgs(script),
      mode: ProcessStartMode.detached,
      environment: environment,
    );
  }
}
