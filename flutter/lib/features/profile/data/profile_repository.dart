import 'dart:io';

import '../../../core/platform/runcore_channel.dart';

class ProfileRepository {
  ProfileRepository({RuncoreChannel? channel})
    : _channel = channel ?? RuncoreChannel();

  final RuncoreChannel _channel;

  Future<void> apply({
    required String contactDirPath,
    required String? avatarPath,
    required String pendingName,
    required String? pendingAvatarPath,
  }) async {
    final contactDir = Directory(contactDirPath);
    if (!contactDir.existsSync()) {
      return;
    }

    final desired = sanitizeFolderName(pendingName);
    var resolvedDir = contactDir;
    if (desired.isNotEmpty) {
      await _channel.setDisplayName(desired);
      final parent = contactDir.parent.path;
      final target = Directory('$parent${Platform.pathSeparator}$desired');
      if (target.existsSync()) {
        resolvedDir = target;
      }
    }

    if (pendingAvatarPath != avatarPath && pendingAvatarPath != null) {
      final src = File(pendingAvatarPath);
      if (src.existsSync()) {
        final ext = src.path.split('.').last.toLowerCase();
        final safeExt = ext.isEmpty ? 'png' : ext;
        final dst = File(
          '${resolvedDir.path}${Platform.pathSeparator}avatar.$safeExt',
        );
        await dst.writeAsBytes(await src.readAsBytes(), flush: true);
      }
    }
  }

  String sanitizeFolderName(String s) {
    s = s.trim();
    if (s.isEmpty) {
      return 'Contact';
    }
    s = s
        .replaceAll(Platform.pathSeparator, '_')
        .replaceAll(':', '_')
        .replaceAll('\u0000', '_');
    if (s.length > 80) {
      s = s.substring(0, 80);
    }
    return s;
  }

}
