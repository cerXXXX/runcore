import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../main.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.contactDirPath,
    required this.displayName,
    required this.lxmfId,
    this.avatarPath,
    this.onClose,
    this.onApplied,
  });

  final String contactDirPath;
  final String displayName;
  final String lxmfId;
  final String? avatarPath;
  final VoidCallback? onClose;
  final VoidCallback? onApplied;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late String _pendingName;
  String? _pendingAvatarPath;

  bool get _dirty => _pendingName != widget.displayName || _pendingAvatarPath != widget.avatarPath;

  @override
  void initState() {
    super.initState();
    _pendingName = widget.displayName;
    _pendingAvatarPath = widget.avatarPath;
  }

  Future<void> _pickAvatar() async {
    final path = await RuncoreChannel.pickImagePath();
    if (!mounted) return;
    if (path == null || path.trim().isEmpty) return;
    setState(() => _pendingAvatarPath = path.trim());
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _pendingName);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Имя'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (res == null) return;
    setState(() => _pendingName = res.trim());
  }

  Future<void> _copyId() async {
    await Clipboard.setData(ClipboardData(text: widget.lxmfId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано')));
  }

  String _sanitizeFolderName(String s) {
    s = s.trim();
    if (s.isEmpty) return 'Contact';
    s = s.replaceAll(Platform.pathSeparator, '_').replaceAll(':', '_').replaceAll('\u0000', '_');
    if (s.length > 80) s = s.substring(0, 80);
    return s;
  }

  Future<void> _apply() async {
    final contactDir = Directory(widget.contactDirPath);
    if (!contactDir.existsSync()) return;

    // 1) Rename folder if name changed.
    final desired = _sanitizeFolderName(_pendingName);
    final currentName = contactDir.path.split(Platform.pathSeparator).last;
    if (desired.isNotEmpty && desired != currentName) {
      final parent = contactDir.parent.path;
      final target = Directory('$parent${Platform.pathSeparator}$desired');
      if (!target.existsSync()) {
        await contactDir.rename(target.path);
      }
    }

    // 2) Write avatar if changed (copy file into avatar.<ext>).
    if (_pendingAvatarPath != widget.avatarPath && _pendingAvatarPath != null) {
      final src = File(_pendingAvatarPath!);
      if (src.existsSync()) {
        final ext = src.path.split('.').last.toLowerCase();
        final safeExt = ext.isEmpty ? 'png' : ext;
        final destDir = Directory(
          '${contactDir.parent.path}${Platform.pathSeparator}${_sanitizeFolderName(_pendingName)}',
        );
        final dst = File('${destDir.path}${Platform.pathSeparator}avatar.$safeExt');
        await dst.writeAsBytes(await src.readAsBytes(), flush: true);
      }
    }

    if (!mounted) return;
    if (widget.onApplied != null) {
      widget.onApplied!();
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = _pendingAvatarPath;
    final canDone = _dirty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(false),
        ),
        title: const Text(''),
        actions: [
          if (canDone)
            TextButton(
              onPressed: _apply,
              child: const Text('Done'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 280,
                    height: 280,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: avatar == null
                        ? Icon(Icons.person, size: 120, color: theme.colorScheme.onSurfaceVariant)
                        : Image.file(File(avatar), fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: theme.colorScheme.surface,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: _pickAvatar,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pendingName.isEmpty ? 'Без имени' : _pendingName,
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _editName,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.lxmfId, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy),
                  onPressed: _copyId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
