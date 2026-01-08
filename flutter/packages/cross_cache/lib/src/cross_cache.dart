import 'dart:typed_data';

/// Minimal stub used by `flutter_chat_ui`.
///
/// The upstream `cross_cache` uses `path_provider` on IO platforms, which pulls
/// CocoaPods plugins on macOS. For runcore we can live without persistent cache
/// at this stage.
class CrossCache {
  Future<void> set(String key, Uint8List value) async {}

  Future<Uint8List> get(String key) async {
    throw StateError('cross_cache stub: cache miss');
  }

  Future<bool> contains(String key) async => false;

  Future<void> delete(String key) async {}

  Future<void> updateKey(String key, String newKey) async {}

  void dispose() {}
}

