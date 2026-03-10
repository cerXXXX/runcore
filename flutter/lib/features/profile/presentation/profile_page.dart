import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/runcore_channel.dart';
import '../data/profile_repository.dart';

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
  final RuncoreChannel _channel = RuncoreChannel();
  final ProfileRepository _repository = ProfileRepository();

  late String _pendingName;
  String? _pendingAvatarPath;

  bool get _dirty =>
      _pendingName != widget.displayName ||
      _pendingAvatarPath != widget.avatarPath;

  @override
  void initState() {
    super.initState();
    _pendingName = widget.displayName;
    _pendingAvatarPath = widget.avatarPath;
  }

  Future<void> _pickAvatar() async {
    final path = await _channel.pickImagePath();
    if (!mounted || path == null || path.trim().isEmpty) {
      return;
    }
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted || res == null) {
      return;
    }
    setState(() => _pendingName = res.trim());
  }

  Future<void> _copyId() async {
    await Clipboard.setData(ClipboardData(text: widget.lxmfId));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Скопировано')));
  }

  Future<void> _apply() async {
    try {
      await _repository.apply(
        contactDirPath: widget.contactDirPath,
        avatarPath: widget.avatarPath,
        pendingName: _pendingName,
        pendingAvatarPath: _pendingAvatarPath,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }

    if (!mounted) {
      return;
    }
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
        title: const Text(''),
        actions: [
          if (canDone) TextButton(onPressed: _apply, child: const Text('Done')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                ClipOval(
                  child: Container(
                    width: 280,
                    height: 280,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: avatar == null
                        ? Icon(
                            Icons.person,
                            size: 120,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
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
                IconButton(icon: const Icon(Icons.edit), onPressed: _editName),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.lxmfId,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
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
