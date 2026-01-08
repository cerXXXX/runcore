import 'dart:io' show Directory;

/// Минимальная заглушка для `path_provider` без нативных плагинов.
///
/// В нашем приложении все пути приходят из runcore (Go), поэтому достаточно
/// возвращать любой доступный каталог. Для совместимости с зависимостями
/// сигнатуры совпадают с оригинальным пакетом.

@Deprecated('This is no longer necessary, and is now a no-op')
set disablePathProviderPlatformOverride(bool override) {}

class MissingPlatformDirectoryException implements Exception {
  MissingPlatformDirectoryException(this.message, {this.details});

  final String message;
  final Object? details;

  @override
  String toString() {
    final detailsAddition = details == null ? '' : ': $details';
    return 'MissingPlatformDirectoryException($message)$detailsAddition';
  }
}

enum StorageDirectory { music, podcasts, ringtones, alarms, notifications, pictures, movies, downloads, dcim, documents }

Future<Directory> getTemporaryDirectory() async => Directory.systemTemp;

Future<Directory> getApplicationSupportDirectory() async => Directory.systemTemp;

Future<Directory> getLibraryDirectory() async => Directory.systemTemp;

Future<Directory> getApplicationDocumentsDirectory() async => Directory.systemTemp;

Future<Directory> getApplicationCacheDirectory() async => Directory.systemTemp;

Future<Directory?> getExternalStorageDirectory() async => null;

Future<List<Directory>?> getExternalCacheDirectories() async => null;

Future<List<Directory>?> getExternalStorageDirectories({StorageDirectory? type}) async => null;

Future<Directory?> getDownloadsDirectory() async => null;

