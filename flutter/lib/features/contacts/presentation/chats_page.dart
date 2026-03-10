import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/platform/runcore_channel.dart';
import '../../chat/presentation/chat_page.dart';
import '../../chat/presentation/chat_view.dart';
import '../../profile/presentation/profile_page.dart';
import '../application/contacts_controller.dart';
import '../data/contacts_repository.dart';
import '../domain/chat_contact.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  late final ContactsController _controller;

  RuncorePaths? _paths;
  String? _error;
  List<ChatContact> _contacts = const [];
  ChatContact? _selectedContact;
  String _contactsQuery = '';
  String _chatQuery = '';
  bool _showChatSearch = false;
  ChatContact? _me;
  bool _showMyProfileInRightPane = false;
  double? _masterWidth;
  bool _showCompactSidebar = true;

  static const double _minMasterWidth = 320;
  static const double _maxMasterWidth = 420;
  static const double _minDetailWidth = 320;
  static const double _dividerWidth = 8;
  static const double _compactCollapseWidth = 820;

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
        _selectedContact = data.selectedContact;
        _showMyProfileInRightPane = data.showMyProfileInRightPane;
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
        _showCompactSidebar = false;
      });
      return;
    }
    setState(() {
      _showMyProfileInRightPane = true;
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
        _showCompactSidebar = false;
        _showChatSearch = false;
        _chatQuery = '';
      });
      return;
    }
    _openChat(p, selected.destHashHex);
  }

  double _masterWidthFor(double width) {
    final target = _masterWidth ?? (width * 0.35);
    final maxAllowed =
        _maxMasterWidth < (width - _minDetailWidth - _dividerWidth)
        ? _maxMasterWidth
        : width - _minDetailWidth - _dividerWidth;
    return target.clamp(_minMasterWidth, maxAllowed);
  }

  bool _isSplitLayout(double width) {
    if (width < _compactCollapseWidth) {
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
    });
  }

  bool get _isCompactDetailVisible =>
      _showMyProfileInRightPane || _selectedContact != null;

  bool get _isChatDetailVisible =>
      !_showMyProfileInRightPane && _selectedContact != null;

  PreferredSizeWidget _buildCompactAppBar() {
    if (_isCompactDetailVisible) {
      return AppBar(
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeCompactDetail,
        ),
        title: const Text(''),
        actions: !_isChatDetailVisible
            ? null
            : [
                IconButton(
                  tooltip: 'Search',
                  icon: Icon(_showChatSearch ? Icons.search_off : Icons.search),
                  onPressed: () => setState(() {
                    _showChatSearch = !_showChatSearch;
                    if (!_showChatSearch) {
                      _chatQuery = '';
                    }
                  }),
                ),
              ],
      );
    }
    return AppBar(
      elevation: 0,
      title: const Text(''),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: _openSearch,
        ),
        IconButton(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildDetailPane(RuncorePaths p) {
    if (_showMyProfileInRightPane && _me != null) {
      return ProfilePage(
        contactDirPath: _me!.dirPath,
        displayName: _me!.name,
        lxmfId: _me!.destHashHex,
        avatarPath: _me!.avatarPath,
        onClose: () => setState(() => _showMyProfileInRightPane = false),
        onApplied: () async {
          setState(() => _showMyProfileInRightPane = false);
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

  Widget _buildContactsList(RuncorePaths p, {required bool isWide}) {
    final items = _filteredContacts();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: [
          for (final c in items)
            SidebarListItem(
              selected:
                  isWide && _selectedContact?.destHashHex == c.destHashHex,
              selectedColor: _selectedItemColor(context),
              onTap: c.destHashHex.isEmpty
                  ? null
                  : () {
                      if (isWide) {
                        setState(() {
                          _selectedContact = c;
                          _showMyProfileInRightPane = false;
                          _showCompactSidebar = false;
                          _showChatSearch = false;
                          _chatQuery = '';
                        });
                      } else {
                        _openChat(p, c.destHashHex);
                      }
                    },
              leading: ContactAvatar(contact: c),
              title: Text(c.name),
              subtitle: Text(
                c.destHashHex.isEmpty ? '(нет lxmf)' : c.destHashHex,
              ),
              trailing: const Icon(Icons.chevron_right, size: 22),
            ),
        ],
      ),
    );
  }

  Widget _buildWideSidebar(RuncorePaths p) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_me != null)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: SidebarListItem(
                  selected: _showMyProfileInRightPane,
                  selectedColor: _selectedItemColor(context),
                  onTap: () {
                    setState(() {
                      _selectedContact = null;
                    });
                    _openMyProfile();
                  },
                  leading: ContactAvatar(contact: _me!, radius: 18),
                  title: Text(
                    _me!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: SizedBox(
                height: 48,
                child: TextField(
                  style: Theme.of(context).textTheme.bodySmall,
                  decoration: _searchDecoration(
                    hintText: 'Search',
                    onClear: _contactsQuery.isEmpty
                        ? null
                        : () => setState(() => _contactsQuery = ''),
                    showClear: _contactsQuery.isNotEmpty,
                  ),
                  onChanged: (v) => setState(() => _contactsQuery = v),
                ),
              ),
            ),
            Expanded(child: _buildContactsList(p, isWide: true)),
          ],
        ),
      ),
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
                    child: _isChatDetailVisible
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _selectedContact?.avatarPath != null
                                  ? CircleAvatar(
                                      radius: 18,
                                      backgroundImage: FileImage(
                                        File(_selectedContact!.avatarPath!),
                                      ),
                                    )
                                  : CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      child: Text(
                                        _selectedContact!.name.isEmpty
                                            ? '?'
                                            : _selectedContact!.name[0]
                                                  .toUpperCase(),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ),
                              const SizedBox(height: 2),
                              Text(
                                _selectedContact!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (_isChatDetailVisible)
                    IconButton(
                      tooltip: 'Search',
                      icon: Icon(
                        _showChatSearch ? Icons.search_off : Icons.search,
                      ),
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
            appBar: showCompactSidebar
                ? AppBar(
                    elevation: 0,
                    title: const Text(''),
                    actions: [
                      IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.search),
                        onPressed: _openSearch,
                      ),
                      IconButton(
                        tooltip: 'More',
                        icon: const Icon(Icons.more_vert),
                        onPressed: () {},
                      ),
                    ],
                  )
                : _buildCompactAppBar(),
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

class ContactAvatar extends StatelessWidget {
  const ContactAvatar({super.key, required this.contact, this.radius});

  final ChatContact contact;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      backgroundImage: contact.avatarPath == null
          ? null
          : FileImage(File(contact.avatarPath!)),
      child: contact.avatarPath == null
          ? Text(contact.name.isEmpty ? '?' : contact.name[0].toUpperCase())
          : null,
    );
    if (radius != null) {
      return avatar;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: avatar,
    );
  }
}

class SidebarListItem extends StatelessWidget {
  const SidebarListItem({
    super.key,
    required this.selected,
    required this.selectedColor,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  static const EdgeInsets outerPadding = EdgeInsets.fromLTRB(10, 2, 10, 2);
  static const EdgeInsets innerPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  final bool selected;
  final Color selectedColor;
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
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
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      title,
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        subtitle!,
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
