import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/platform/runcore_channel.dart';
import '../domain/chat_contact.dart';

class ChatsSidebar extends StatelessWidget {
  const ChatsSidebar({
    super.key,
    required this.me,
    required this.interfaces,
    required this.announces,
    required this.contacts,
    required this.selectedContact,
    required this.showMyProfileInRightPane,
    required this.selectedColor,
    required this.contactsQuery,
    required this.onContactsQueryChanged,
    required this.onClearContactsQuery,
    required this.onOpenMyProfile,
    required this.onAddContact,
    required this.onOpenRadar,
    required this.onSelectContact,
    required this.onRefresh,
  });

  final ChatContact? me;
  final List<RuncoreInterfaceStatus> interfaces;
  final List<RuncoreAnnounce> announces;
  final List<ChatContact> contacts;
  final ChatContact? selectedContact;
  final bool showMyProfileInRightPane;
  final Color selectedColor;
  final String contactsQuery;
  final ValueChanged<String> onContactsQueryChanged;
  final VoidCallback? onClearContactsQuery;
  final VoidCallback onOpenMyProfile;
  final VoidCallback onAddContact;
  final VoidCallback onOpenRadar;
  final ValueChanged<ChatContact> onSelectContact;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (me != null)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: SidebarContactTile(
                  selected: showMyProfileInRightPane,
                  selectedColor: selectedColor,
                  onTap: onOpenMyProfile,
                  contact: me!,
                  subtitle: InterfaceStatusRow(interfaces: interfaces),
                  trailingLabel: '',
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: SizedBox(
                height: 48,
                child: TextField(
                  style: Theme.of(context).textTheme.bodySmall,
                  decoration: _sidebarSearchDecoration(
                    contactsQuery.isNotEmpty,
                    onClearContactsQuery,
                  ),
                  onChanged: onContactsQueryChanged,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView(
                  children: [
                    for (final c in contacts)
                      SidebarContactTile(
                        selected: selectedContact?.destHashHex == c.destHashHex,
                        selectedColor: selectedColor,
                        onTap: c.destHashHex.isEmpty
                            ? null
                            : () => onSelectContact(c),
                        contact: c,
                        subtitle: Text(
                          c.destHashHex.isEmpty ? '(нет lxmf)' : c.destHashHex,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailingLabel: _lastSeenLabelFor(c.destHashHex),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Add contact by id',
                    icon: const Icon(Icons.add),
                    onPressed: onAddContact,
                  ),
                  IconButton(
                    tooltip: 'Network radar',
                    icon: const Icon(Icons.radar),
                    onPressed: onOpenRadar,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _sidebarSearchDecoration(
    bool showClear,
    VoidCallback? onClear,
  ) {
    final radius = BorderRadius.circular(999);
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: 'Search',
      filled: true,
      fillColor: const Color(0x14000000),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      suffixIcon: showClear
          ? IconButton(
              tooltip: 'Clear',
              padding: const EdgeInsets.only(right: 4),
              constraints: const BoxConstraints.tightFor(width: 28, height: 24),
              icon: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0x14000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.clear, size: 12),
              ),
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onPressed: onClear,
            )
          : null,
      suffixIconConstraints: const BoxConstraints.tightFor(
        width: 24,
        height: 24,
      ),
    );
  }

  String _lastSeenLabelFor(String destHashHex) {
    final normalized = destHashHex.trim().toLowerCase();
    for (final item in announces) {
      if (item.destinationHashHex.trim().toLowerCase() == normalized) {
        return _formatLastSeen(item.lastSeen);
      }
    }
    return 'был давно';
  }

  String _formatLastSeen(int unixSeconds) {
    if (unixSeconds <= 0) {
      return 'был давно';
    }
    final announcedAt = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
    );
    final diff = DateTime.now().difference(announcedAt);
    if (diff.inSeconds < 60) {
      return 'just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} h ago';
    }
    return '${diff.inDays} d ago';
  }
}

class SidebarContactTile extends StatelessWidget {
  const SidebarContactTile({
    super.key,
    required this.selected,
    required this.selectedColor,
    required this.contact,
    required this.subtitle,
    required this.trailingLabel,
    this.onTap,
  });

  static const EdgeInsets outerPadding = EdgeInsets.fromLTRB(10, 2, 10, 2);
  static const EdgeInsets innerPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  final bool selected;
  final Color selectedColor;
  final ChatContact contact;
  final Widget subtitle;
  final String trailingLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: outerPadding,
      child: Material(
        color: selected ? selectedColor : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: innerPadding,
            child: Row(
              children: [
                ContactAvatar(contact: contact, radius: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              contact.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (trailingLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              trailingLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: const Color(0xFF8A8F98)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      subtitle,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InterfaceStatusRow extends StatelessWidget {
  const InterfaceStatusRow({super.key, required this.interfaces});

  final List<RuncoreInterfaceStatus> interfaces;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (interfaces.isEmpty) {
      return Icon(
        Icons.cloud_off,
        size: 14,
        color: const Color(0xFF8A8F98),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        for (final item in interfaces)
          Tooltip(
            message: item.online
                ? '${item.displayName}: online'
                : '${item.displayName}: offline',
            child: Icon(
              _iconForInterface(item.type),
              size: 14,
              color: item.online
                  ? const Color(0xFF2F9E44)
                  : const Color(0xFF8A8F98),
            ),
          ),
      ],
    );
  }

  IconData _iconForInterface(String type) {
    final value = type.toLowerCase();
    if (value.contains('tcp')) {
      return Icons.language;
    }
    if (value.contains('ble') || value.contains('bluetooth')) {
      return Icons.bluetooth;
    }
    if (value.contains('serial') || value.contains('rnode')) {
      return Icons.usb;
    }
    if (value.contains('auto')) {
      return Icons.wifi_tethering;
    }
    if (value.contains('local') || value.contains('shared')) {
      return Icons.lan;
    }
    return Icons.hub;
  }
}

class ContactAvatar extends StatelessWidget {
  const ContactAvatar({super.key, required this.contact, this.radius});

  final ChatContact contact;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final avatar = AvatarCircle(
      radius: radius ?? 24,
      avatarPath: contact.avatarPath,
      name: contact.name,
      colorSeed: contact.destHashHex,
    );
    if (radius != null) {
      return avatar;
    }
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 8),
      child: avatar,
    );
  }
}

class AvatarCircle extends StatelessWidget {
  const AvatarCircle({
    required this.radius,
    required this.avatarPath,
    required this.name,
    this.colorSeed,
  });

  final double radius;
  final String? avatarPath;
  final String name;
  final String? colorSeed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = avatarPath?.trim();
    final size = radius * 2;

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: _avatarColorFromSeed(
          colorSeed?.trim().isNotEmpty == true ? colorSeed! : name,
        ),
        child: path == null || path.isEmpty
            ? _AvatarFallback(name: name, radius: radius)
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _AvatarFallback(name: name, radius: radius);
                },
              ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name, required this.radius});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1F2933),
        ),
      ),
    );
  }
}

Color _avatarColorFromSeed(String seed) {
  final normalized = seed.trim().toLowerCase();
  var hash = 0;
  for (final codeUnit in normalized.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  final saturation = 0.50 + ((hash >> 4) % 12) / 100;
  final lightness = 0.62 + ((hash >> 9) % 8) / 100;
  return HSLColor.fromAHSL(
    1,
    hue,
    saturation.clamp(0.50, 0.62),
    lightness.clamp(0.62, 0.70),
  ).toColor();
}
