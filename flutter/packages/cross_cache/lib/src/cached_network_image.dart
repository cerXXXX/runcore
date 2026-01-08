import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'cross_cache.dart';

/// Non-caching replacement for upstream `CachedNetworkImage`.
///
/// Accepts the same constructor shape used by `flutter_chat_ui` but delegates to
/// `NetworkImage`.
@immutable
class CachedNetworkImage extends ImageProvider<NetworkImage> {
  CachedNetworkImage(
    String url,
    CrossCache _cache, {
    Map<String, dynamic>? headers,
  }) : _inner = NetworkImage(url, headers: _stringHeaders(headers));

  final NetworkImage _inner;

  @override
  Future<NetworkImage> obtainKey(ImageConfiguration configuration) {
    return _inner.obtainKey(configuration);
  }

  @override
  ImageStreamCompleter loadBuffer(NetworkImage key, DecoderBufferCallback decode) {
    return _inner.loadBuffer(key, decode);
  }

  @override
  ImageStreamCompleter loadImage(NetworkImage key, ImageDecoderCallback decode) {
    return _inner.loadImage(key, decode);
  }

  static Map<String, String>? _stringHeaders(Map<String, dynamic>? headers) {
    if (headers == null || headers.isEmpty) return null;
    final out = <String, String>{};
    for (final entry in headers.entries) {
      out[entry.key] = entry.value?.toString() ?? '';
    }
    return out;
  }

  @override
  bool operator ==(Object other) => other is CachedNetworkImage && other._inner == _inner;

  @override
  int get hashCode => _inner.hashCode;
}
