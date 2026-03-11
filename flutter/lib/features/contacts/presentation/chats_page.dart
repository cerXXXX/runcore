import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/platform/runcore_channel.dart';
import '../../chat/presentation/chat_page.dart';
import '../../chat/presentation/chat_view.dart';
import '../../profile/presentation/profile_page.dart';
import '../application/contacts_controller.dart';
import '../data/contacts_repository.dart';
import '../domain/chat_contact.dart';
import 'chats_sidebar.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  late final ContactsController _controller;
  Timer? _refreshTimer;

  RuncorePaths? _paths;
  String? _error;
  List<ChatContact> _contacts = const [];
  ChatContact? _selectedContact;
  String _contactsQuery = '';
  String _chatQuery = '';
  bool _showChatSearch = false;
  ChatContact? _me;
  List<RuncoreInterfaceStatus> _interfaces = const [];
  List<RuncoreAnnounce> _announces = const [];
  bool _showMyProfileInRightPane = false;
  bool _showSelectedContactProfileInRightPane = false;
  double? _masterWidth;
  bool _showCompactSidebar = true;

  static const double _minMasterWidth = 260;
  static const double _maxMasterWidth = 320;
  static const double _minDetailWidth = 320;
  static const double _dividerWidth = 8;

  Color _selectedItemColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.colorScheme.primary.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.12,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = ContactsController(
      repository: ContactsRepository(channel: RuncoreChannel()),
    );
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }
    setState(() => _error = null);
    try {
      final data = await _controller.refresh(
        selectedContact: _selectedContact,
        showMyProfileInRightPane: _showMyProfileInRightPane,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _paths = data.paths;
        _contacts = data.contacts;
        _me = data.me;
        _interfaces = data.interfaces;
        _announces = data.announces;
        _selectedContact = data.selectedContact;
        _showMyProfileInRightPane = data.showMyProfileInRightPane;
        if (_selectedContact == null) {
          _showSelectedContactProfileInRightPane = false;
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '$e');
    }
  }

  Future<void> _openMyProfile() async {
    final me = _me;
    if (me == null) {
      return;
    }
    final isWide = _isSplitLayout(MediaQuery.sizeOf(context).width);
    if (isWide) {
      setState(() {
        _showMyProfileInRightPane = true;
        _showSelectedContactProfileInRightPane = false;
        _showCompactSidebar = false;
      });
      return;
    }
    setState(() {
      _showMyProfileInRightPane = true;
      _showSelectedContactProfileInRightPane = false;
      _showCompactSidebar = false;
    });
  }

  void _openChat(RuncorePaths p, String dest) {
    final normalized = dest.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }
    final match = _contacts.where((c) => c.destHashHex == normalized);
    if (match.isNotEmpty) {
      setState(() {
        _selectedContact = match.first;
        _showMyProfileInRightPane = false;
        _showSelectedContactProfileInRightPane = false;
        _showCompactSidebar = false;
        _showChatSearch = false;
        _chatQuery = '';
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(paths: p, destHashHex: normalized),
      ),
    );
  }

  Future<void> _openSearch() async {
    final p = _paths;
    if (p == null) {
      return;
    }
    final selected = await showSearch<ChatContact?>(
      context: context,
      delegate: ContactsSearchDelegate(_contacts),
    );
    if (!mounted || selected == null || selected.destHashHex.isEmpty) {
      return;
    }
    final isWide = _isSplitLayout(MediaQuery.sizeOf(context).width);
    if (isWide) {
      setState(() {
        _selectedContact = selected;
        _showMyProfileInRightPane = false;
        _showSelectedContactProfileInRightPane = false;
        _showCompactSidebar = false;
        _showChatSearch = false;
        _chatQuery = '';
      });
      return;
    }
    _openChat(p, selected.destHashHex);
  }

  Future<void> _addContactById() async {
    final paths = _paths;
    if (paths == null) {
      return;
    }
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить контакт'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'LXMF id',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Отменить'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    final destinationId = (input ?? '').trim();
    if (!mounted || destinationId.isEmpty) {
      return;
    }
    try {
      final contact = await _controller.addContactById(
        paths.contactsDir,
        destinationId,
        null,
      );
      await _refresh();
      if (!mounted || contact == null || contact.destHashHex.isEmpty) {
        return;
      }
      setState(() {
        _selectedContact = contact;
        _showMyProfileInRightPane = false;
        _showSelectedContactProfileInRightPane = false;
        _showCompactSidebar = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openRadar() async {
    final announces = await _loadRadarAnnounces();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setRadarState) => AlertDialog(
          title: const Text('Network radar'),
          content: SizedBox(
            width: 420,
            child: SizedBox(
              height: 320,
              child: _RadarList(
                entries: announces,
                onTapEntry: (entry) async {
                  final addedId = await _promptAddContact(entry);
                  if (addedId != null) {
                    final refreshed = await _loadRadarAnnounces();
                    if (!ctx.mounted) {
                      return;
                    }
                    setRadarState(() {
                      announces.removeWhere(
                        (item) =>
                            item.destinationHashHex.trim().toLowerCase() ==
                            addedId.trim().toLowerCase(),
                      );
                      announces
                        ..clear()
                        ..addAll(refreshed);
                    });
                  }
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<RuncoreAnnounce>> _loadRadarAnnounces() async {
    final allAnnounces = await RuncoreChannel().getAnnounces();
    final knownIds =
        _contacts.map((c) => c.destHashHex.trim().toLowerCase()).toSet();
    if (_me != null && _me!.destHashHex.isNotEmpty) {
      knownIds.add(_me!.destHashHex.trim().toLowerCase());
    }
    return allAnnounces
        .where(
          (item) =>
              !knownIds.contains(item.destinationHashHex.trim().toLowerCase()),
        )
        .toList(growable: true);
  }

  Future<String?> _promptAddContact(RuncoreAnnounce entry) async {
    final paths = _paths;
    if (paths == null) {
      return null;
    }
    final initialName = entry.displayName.trim();
    final needsNameInput = initialName.isEmpty;
    final nameController = TextEditingController(text: initialName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить контакт'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                entry.destinationHashHex,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              if (needsNameInput) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Имя контакта',
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  initialName,
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отменить'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return null;
    }
    try {
      final contact = await _controller.addContactById(
        paths.contactsDir,
        entry.destinationHashHex,
        needsNameInput ? nameController.text : initialName,
      );
      await _refresh();
      if (!mounted || contact == null || contact.destHashHex.isEmpty) {
        return null;
      }
      setState(() {
        _selectedContact = contact;
        _showMyProfileInRightPane = false;
        _showSelectedContactProfileInRightPane = false;
        _showCompactSidebar = false;
      });
      return contact.destHashHex;
    } catch (e) {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return null;
    }
  }

  double _masterWidthFor(double width) {
    final target = _masterWidth ?? (width * 0.35);
    final available = width - _minDetailWidth - _dividerWidth;
    final maxAllowed = available < _maxMasterWidth ? available : _maxMasterWidth;
    if (maxAllowed <= _minMasterWidth) {
      return _minMasterWidth;
    }
    return target.clamp(_minMasterWidth, maxAllowed);
  }

  bool _isSplitLayout(double width) {
    if (width - _minDetailWidth - _dividerWidth <= _minMasterWidth) {
      return false;
    }
    final master = _masterWidthFor(width);
    final detail = width - master - _dividerWidth;
    return master >= _minMasterWidth && detail >= _minDetailWidth;
  }

  void _resizeSidebar(double delta, double totalWidth) {
    final next = (_masterWidthFor(totalWidth) + delta).clamp(
      _minMasterWidth,
      _maxMasterWidth,
    );
    setState(() => _masterWidth = next);
  }

  void _closeCompactDetail() {
    setState(() {
      _showCompactSidebar = true;
      _showChatSearch = false;
      _chatQuery = '';
      _selectedContact = null;
      _showMyProfileInRightPane = false;
      _showSelectedContactProfileInRightPane = false;
    });
  }

  bool get _isCompactDetailVisible =>
      _showMyProfileInRightPane ||
      _showSelectedContactProfileInRightPane ||
      _selectedContact != null;

  bool get _isChatDetailVisible =>
      !_showMyProfileInRightPane &&
      !_showSelectedContactProfileInRightPane &&
      _selectedContact != null;

  String _lastSeenLabelFor(String destHashHex) {
    final normalized = destHashHex.trim().toLowerCase();
    for (final item in _announces) {
      if (item.destinationHashHex.trim().toLowerCase() == normalized) {
        return formatLastSeen(item.lastSeen);
      }
    }
    return 'был давно';
  }

  Widget _buildCompactToolbar({required bool showCompactSidebar}) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              if (!showCompactSidebar)
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _closeCompactDetail,
                ),
              if (!showCompactSidebar)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child:
                          (_isChatDetailVisible ||
                              _showSelectedContactProfileInRightPane)
                          ? _buildSelectedContactHeaderCell()
                          : const SizedBox.shrink(),
                    ),
                  ),
                )
              else
                const Spacer(),
              if (!showCompactSidebar && _isChatDetailVisible)
                _searchToggleButton(
                  onPressed: () => setState(() {
                    _showChatSearch = !_showChatSearch;
                    if (!_showChatSearch) {
                      _chatQuery = '';
                    }
                  }),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPane(RuncorePaths p) {
    if (_showMyProfileInRightPane && _me != null) {
      return ProfilePage(
        key: ValueKey('me:${_me!.dirPath}'),
        contactDirPath: _me!.dirPath,
        displayName: _me!.name,
        lxmfId: _me!.destHashHex,
        avatarPath: _me!.avatarPath,
        isSelfProfile: true,
        allowReset: true,
        onClose: () => setState(() => _showMyProfileInRightPane = false),
        onApplied: () async {
          setState(() => _showMyProfileInRightPane = false);
          await _refresh();
        },
      );
    }
    if (_showSelectedContactProfileInRightPane && _selectedContact != null) {
      return ProfilePage(
        key: ValueKey('contact:${_selectedContact!.dirPath}'),
        contactDirPath: _selectedContact!.dirPath,
        displayName: _selectedContact!.name,
        lxmfId: _selectedContact!.destHashHex,
        avatarPath: _selectedContact!.avatarPath,
        embedded: true,
        isSelfProfile: false,
        allowContactDelete: true,
        onClose: () => setState(() {
          _showSelectedContactProfileInRightPane = false;
        }),
        onApplied: () async {
          setState(() => _showSelectedContactProfileInRightPane = false);
          await _refresh();
        },
      );
    }
    if (_selectedContact == null) {
      return const SizedBox.shrink();
    }
    return ChatView(
      paths: p,
      destHashHex: _selectedContact!.destHashHex,
      query: _chatQuery,
    );
  }

  Color _dividerColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF5E6470)
        : const Color(0xFFC9CDD4);
  }

  List<ChatContact> _filteredContacts() {
    final q = _contactsQuery.trim().toLowerCase();
    if (q.isEmpty) {
      return _contacts;
    }
    return _contacts
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.destHashHex.toLowerCase().contains(q),
        )
        .toList();
  }

  InputDecoration _searchDecoration({
    required String hintText,
    required VoidCallback? onClear,
    bool showClear = true,
  }) {
    final radius = BorderRadius.circular(999);
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hintText,
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

  Widget _searchToggleButton({required VoidCallback onPressed}) {
    return IconButton(
      tooltip: 'Search',
      icon: const Icon(Icons.search),
      style: IconButton.styleFrom(
        backgroundColor: _showChatSearch ? _selectedItemColor(context) : null,
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildSelectedContactHeaderCell() {
    final contact = _selectedContact;
    if (contact == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: _showSelectedContactProfileInRightPane
          ? _selectedItemColor(context)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          _showSelectedContactProfileInRightPane =
              !_showSelectedContactProfileInRightPane;
          _showMyProfileInRightPane = false;
          _showChatSearch = false;
          if (!_showSelectedContactProfileInRightPane) {
            _chatQuery = '';
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarCircle(
                radius: 16,
                avatarPath: contact.avatarPath,
                name: contact.name,
                colorSeed: contact.destHashHex,
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _lastSeenLabelFor(contact.destHashHex),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideSidebar(RuncorePaths p) {
    return ChatsSidebar(
      me: _me,
      interfaces: _interfaces,
      announces: _announces,
      contacts: _filteredContacts(),
      selectedContact: _selectedContact,
      showMyProfileInRightPane: _showMyProfileInRightPane,
      selectedColor: _selectedItemColor(context),
      contactsQuery: _contactsQuery,
      onContactsQueryChanged: (v) => setState(() => _contactsQuery = v),
      onClearContactsQuery: _contactsQuery.isEmpty
          ? null
          : () => setState(() => _contactsQuery = ''),
      onOpenMyProfile: () {
        setState(() {
          _selectedContact = null;
          _showSelectedContactProfileInRightPane = false;
        });
        _openMyProfile();
      },
      onAddContact: _addContactById,
      onOpenRadar: _openRadar,
      onSelectContact: (c) {
        if (_isSplitLayout(MediaQuery.sizeOf(context).width)) {
          setState(() {
            _selectedContact = c;
            _showMyProfileInRightPane = false;
            _showSelectedContactProfileInRightPane = false;
            _showCompactSidebar = false;
            _showChatSearch = false;
            _chatQuery = '';
          });
          return;
        }
        _openChat(p, c.destHashHex);
      },
      onRefresh: _refresh,
    );
  }

  Widget _buildCompactSidebar(RuncorePaths p) {
    return Column(children: [Expanded(child: _buildWideSidebar(p))]);
  }

  Widget _buildWideDetail(RuncorePaths p) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  Expanded(
                    child:
                        (_isChatDetailVisible ||
                            _showSelectedContactProfileInRightPane)
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _buildSelectedContactHeaderCell(),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (_isChatDetailVisible)
                    _searchToggleButton(
                      onPressed: () => setState(() {
                        _showChatSearch = !_showChatSearch;
                        if (!_showChatSearch) {
                          _chatQuery = '';
                        }
                      }),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (_isChatDetailVisible && _showChatSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: _searchDecoration(
                        hintText: 'Search in chat',
                        onClear: _chatQuery.isEmpty
                            ? null
                            : () => setState(() => _chatQuery = ''),
                        showClear: true,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                      onChanged: (v) => setState(() => _chatQuery = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Previous match',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: _chatQuery.isEmpty ? null : () {},
                  ),
                  IconButton(
                    tooltip: 'Next match',
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: _chatQuery.isEmpty ? null : () {},
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildDetailPane(p)),
        ],
      ),
    );
  }

  Widget _buildCompactDetailBody(
    RuncorePaths p, {
    required bool showCompactSidebar,
  }) {
    return Column(
      children: [
        if (!showCompactSidebar)
          _buildCompactToolbar(showCompactSidebar: showCompactSidebar),
        if (!showCompactSidebar && _isChatDetailVisible && _showChatSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: _searchDecoration(
                      hintText: 'Search in chat',
                      onClear: _chatQuery.isEmpty
                          ? null
                          : () => setState(() => _chatQuery = ''),
                      showClear: true,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                    onChanged: (v) => setState(() => _chatQuery = v),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Previous match',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: _chatQuery.isEmpty ? null : () {},
                ),
                IconButton(
                  tooltip: 'Next match',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: _chatQuery.isEmpty ? null : () {},
                ),
              ],
            ),
          ),
        Expanded(
          child: showCompactSidebar
              ? _buildCompactSidebar(p)
              : _buildDetailPane(p),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _paths;
    if (p == null) {
      return Scaffold(body: Center(child: Text(_error ?? 'Загрузка…')));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isWide = _isSplitLayout(w);
        if (!isWide) {
          final showCompactSidebar =
              !_isCompactDetailVisible || _showCompactSidebar;
          return Scaffold(
            body: _buildCompactDetailBody(
              p,
              showCompactSidebar: showCompactSidebar,
            ),
          );
        }

        return Scaffold(
          body: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Row(
              children: [
                SizedBox(
                  width: _masterWidthFor(w),
                  child: _buildWideSidebar(p),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) =>
                        _resizeSidebar(details.delta.dx, w),
                    child: SizedBox(
                      width: _dividerWidth,
                      child: Center(
                        child: Container(
                          width: 2,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _dividerColor(context),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: _buildWideDetail(p)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RadarList extends StatelessWidget {
  const _RadarList({required this.entries, required this.onTapEntry});

  final List<RuncoreAnnounce> entries;
  final ValueChanged<RuncoreAnnounce> onTapEntry;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('Nothing discovered yet'));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final item = entries[index];
        return ListTile(
          leading: AvatarCircle(
            radius: 20,
            avatarPath: null,
            name: item.title,
            colorSeed: item.destinationHashHex,
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            formatLastSeen(item.lastSeen),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onTapEntry(item),
        );
      },
    );
  }

}

String formatLastSeen(int unixSeconds) {
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

class ContactsSearchDelegate extends SearchDelegate<ChatContact?> {
  ContactsSearchDelegate(this.contacts);

  final List<ChatContact> contacts;

  @override
  String get searchFieldLabel => 'Поиск';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  List<ChatContact> _filter() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return contacts;
    }
    return contacts
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.destHashHex.toLowerCase().contains(q),
        )
        .toList();
  }

  Widget _buildList(BuildContext context) {
    final items = _filter();
    if (items.isEmpty) {
      return const Center(child: Text('Ничего не найдено'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final c = items[i];
        return ListTile(
          leading: ContactAvatar(contact: c),
          title: Text(c.name),
          subtitle: Text(c.destHashHex.isEmpty ? '(нет lxmf)' : c.destHashHex),
          enabled: c.destHashHex.isNotEmpty,
          onTap: c.destHashHex.isEmpty ? null : () => close(context, c),
        );
      },
    );
  }
}
