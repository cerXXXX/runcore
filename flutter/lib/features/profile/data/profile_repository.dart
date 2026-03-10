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
    required bool isSelfProfile,
  }) async {
    final contactDir = Directory(contactDirPath);
    if (!contactDir.existsSync()) {
      return;
    }

    final desired = sanitizeFolderName(pendingName);
    var resolvedDir = contactDir;
    if (desired.isNotEmpty) {
      final parent = contactDir.parent.path;
      final target = Directory('$parent${Platform.pathSeparator}$desired');
      if (isSelfProfile) {
        await _channel.setDisplayName(desired);
        if (target.existsSync()) {
          resolvedDir = target;
        }
      } else if (contactDir.path != target.path) {
        if (!target.existsSync()) {
          resolvedDir = await contactDir.rename(target.path);
        } else {
          resolvedDir = target;
        }
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

  Future<void> resetProfile() async {
    await _channel.resetProfile();
  }

  Future<void> deleteContactLXMF(String contactDirPath) async {
    final lxmfFile = File(
      '$contactDirPath${Platform.pathSeparator}lxmf',
    );
    if (lxmfFile.existsSync()) {
      await lxmfFile.delete();
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
