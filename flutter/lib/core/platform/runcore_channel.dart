import 'package:flutter/services.dart';

class RuncorePaths {
  const RuncorePaths({
    required this.contactsDir,
    required this.sendDir,
    required this.messagesDir,
    required this.configDir,
  });

  final String contactsDir;
  final String sendDir;
  final String messagesDir;
  final String configDir;

  bool get isValid =>
      contactsDir.isNotEmpty && sendDir.isNotEmpty && messagesDir.isNotEmpty;
}

class RuncoreChannel {
  RuncoreChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('runcore');

  final MethodChannel _channel;

  Future<RuncorePaths> getPaths() async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getPaths');
    if (res == null) {
      throw StateError('getPaths вернул null');
    }
    return RuncorePaths(
      contactsDir: (res['contactsDir'] as String?) ?? '',
      sendDir: (res['sendDir'] as String?) ?? '',
      messagesDir: (res['messagesDir'] as String?) ?? '',
      configDir: (res['configDir'] as String?) ?? '',
    );
  }

  Future<String> getMeContactName() async {
    final res = await _channel.invokeMethod<String>('getMeContactName');
    return (res ?? '').trim();
  }

  Future<String?> pickImagePath() async {
    final res = await _channel.invokeMethod<String>('pickImagePath');
    final v = (res ?? '').trim();
    return v.isEmpty ? null : v;
  }
}
