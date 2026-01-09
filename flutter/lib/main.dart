import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:uuid/uuid.dart';
import 'ui/profile/profile_page.dart';

void main() => runApp(const RuncoreApp());

class RuncoreApp extends StatelessWidget {
  const RuncoreApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    final bg = brightness == Brightness.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final scheme = base.colorScheme.copyWith(
      surface: bg,
      surfaceContainerLowest: bg,
      surfaceContainerLow: bg,
      surfaceContainer: bg,
      surfaceContainerHigh: bg,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: bg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: const DividerThemeData(color: Color(0x0A000000), thickness: 1, space: 1),
      dividerColor: brightness == Brightness.dark
          ? const Color(0x0AFFFFFF)
          : const Color(0x0A000000),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Runcore',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        // Чуть уменьшаем масштаб текста, чтобы интерфейс не выглядел "слишком крупным".
        const uiTextScale = 0.92;
        return MediaQuery(
          data: media.copyWith(textScaler: const TextScaler.linear(uiTextScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const ChatsPage(),
    );
  }
}

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

  bool get isValid => contactsDir.isNotEmpty && sendDir.isNotEmpty && messagesDir.isNotEmpty;
}

class RuncoreChannel {
  static const _channel = MethodChannel('runcore');

  static Future<RuncorePaths> getPaths() async {
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

  static Future<String> getMeContactName() async {
    final res = await _channel.invokeMethod<String>('getMeContactName');
    return (res ?? '').trim();
  }

  static Future<String?> pickImagePath() async {
    final res = await _channel.invokeMethod<String>('pickImagePath');
    final v = (res ?? '').trim();
    return v.isEmpty ? null : v;
  }
}

class ChatContact {
  const ChatContact({
    required this.name,
    required this.destHashHex,
    required this.dirPath,
    required this.avatarPath,
  });

  final String name;
  final String destHashHex;
  final String dirPath;
  final String? avatarPath;
}

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  RuncorePaths? _paths;
  String? _error;
  List<ChatContact> _contacts = const [];
  ChatContact? _selectedContact; // for wide layouts
  String _contactsQuery = '';
  String _chatQuery = '';
  ChatContact? _me;
  bool _showMyProfileInRightPane = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _error = null;
    });
    try {
      final p = await RuncoreChannel.getPaths();
      if (!p.isValid) throw StateError('Пути пустые: $p');
      final meName = await RuncoreChannel.getMeContactName();
      final me = await _loadMeContact(p.contactsDir, meName);
      final contacts = await _loadContacts(p.contactsDir, meContactName: meName);
      setState(() {
        _paths = p;
        _contacts = contacts;
        _me = me;
        if (_selectedContact != null) {
          _selectedContact = contacts.firstWhere(
            (c) => c.destHashHex == _selectedContact!.destHashHex,
            orElse: () => _selectedContact!,
          );
          if (_selectedContact!.destHashHex.isEmpty ||
              !contacts.any((c) => c.destHashHex == _selectedContact!.destHashHex)) {
            _selectedContact = null;
          }
        }
        if (_me == null) {
          _showMyProfileInRightPane = false;
        }
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  static bool _isHiddenName(String name) => name.startsWith('.');

  Future<List<ChatContact>> _loadContacts(String contactsDir, {required String meContactName}) async {
    final out = <ChatContact>[];
    try {
      final d = Directory(contactsDir);
      if (!d.existsSync()) return const [];
      final entries = d.listSync(followLinks: false).whereType<Directory>().toList();
      entries.sort((a, b) => a.path.compareTo(b.path));

      for (final dir in entries) {
        final name = dir.path.split(Platform.pathSeparator).last;
        if (_isHiddenName(name)) continue;
        if (meContactName.isNotEmpty && name == meContactName) continue;

        final lxmfFile = File('${dir.path}${Platform.pathSeparator}lxmf');
        final dest = lxmfFile.existsSync()
            ? (await lxmfFile.readAsString().catchError((_) => '')).trim().toLowerCase()
            : '';

        String? avatarPath;
        try {
          final files = dir
              .listSync(followLinks: false)
              .whereType<File>()
              .where((f) => f.path.split(Platform.pathSeparator).last.toLowerCase().startsWith('avatar.'))
              .toList();
          if (files.isNotEmpty) {
            files.sort((a, b) => a.path.compareTo(b.path));
            avatarPath = files.first.path;
          }
        } catch (_) {}

        out.add(
          ChatContact(
            name: name,
            destHashHex: dest,
            dirPath: dir.path,
            avatarPath: avatarPath,
          ),
        );
      }
    } catch (_) {
      return const [];
    }

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<ChatContact?> _loadMeContact(String contactsDir, String meName) async {
    meName = meName.trim();
    if (meName.isEmpty) return null;
    final dirPath = '$contactsDir${Platform.pathSeparator}$meName';
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;

    final lxmfFile = File('${dir.path}${Platform.pathSeparator}lxmf');
    final dest = lxmfFile.existsSync()
        ? (await lxmfFile.readAsString().catchError((_) => '')).trim().toLowerCase()
        : '';

    String? avatarPath;
    try {
      final files = dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => f.path.split(Platform.pathSeparator).last.toLowerCase().startsWith('avatar.'))
          .toList();
      if (files.isNotEmpty) {
        files.sort((a, b) => a.path.compareTo(b.path));
        avatarPath = files.first.path;
      }
    } catch (_) {}

    return ChatContact(
      name: meName,
      destHashHex: dest,
      dirPath: dir.path,
      avatarPath: avatarPath,
    );
  }

  Future<void> _openMyProfile() async {
    final me = _me;
    if (me == null) return;
    final isWide = MediaQuery.sizeOf(context).width >= _splitThreshold;
    if (isWide) {
      setState(() => _showMyProfileInRightPane = true);
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => ProfilePage(
          contactDirPath: me.dirPath,
          displayName: me.name,
          lxmfId: me.destHashHex,
          avatarPath: me.avatarPath,
        ),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      await _refresh();
    }
  }

  void _openChat(RuncorePaths p, String dest) {
    dest = dest.trim().toLowerCase();
    if (dest.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(paths: p, destHashHex: dest),
      ),
    );
  }

  Future<void> _openSearch() async {
    final p = _paths;
    if (p == null) return;
    final selected = await showSearch<ChatContact?>(
      context: context,
      delegate: _ContactsSearchDelegate(_contacts),
    );
    if (!mounted) return;
    if (selected == null) return;
    if (selected.destHashHex.isEmpty) return;
    final isWide = MediaQuery.sizeOf(context).width >= _splitThreshold;
    if (isWide) {
      setState(() {
        _selectedContact = selected;
        _showMyProfileInRightPane = false;
      });
      return;
    }
    _openChat(p, selected.destHashHex);
  }

  static const double _splitThreshold = 900;
  static const double _minMasterWidth = 320;
  static const double _maxMasterWidth = 420;
  static const double _minDetailWidth = 320;

  double _masterWidthFor(double width) {
    final target = width * 0.35;
    return target.clamp(_minMasterWidth, _maxMasterWidth);
  }

  bool _canSplit(double width) {
    final master = _masterWidthFor(width);
    final detail = width - master - 1;
    return detail >= _minDetailWidth;
  }

  Color _dividerColor(BuildContext context) {
    // Явно задаём цвет, чтобы Divider/VerticalDivider точно брали его из этого места.
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0x0AFFFFFF)
        : const Color(0x0A000000);
  }

  List<ChatContact> _filteredContacts() {
    final q = _contactsQuery.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts
        .where((c) => c.name.toLowerCase().contains(q) || c.destHashHex.toLowerCase().contains(q))
        .toList();
  }

  InputDecoration _searchDecoration({
    required BuildContext context,
    required String hintText,
    required VoidCallback? onClear,
    bool showClear = true,
  }) {
    final fill = const Color(0x14000000);

    final radius = BorderRadius.circular(999);
    final border = OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none);
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: fill,
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
                child: Icon(Icons.clear, size: 12),
              ),
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onPressed: onClear,
            )
          : null,
      suffixIconConstraints: const BoxConstraints.tightFor(width: 24, height: 24),
    );
  }

  Widget _buildContactsList(RuncorePaths p, {required bool isWide}) {
    final items = _filteredContacts();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: [
          for (final c in items)
            ListTile(
              dense: true,
              selected: isWide && _selectedContact?.destHashHex == c.destHashHex,
              onTap: c.destHashHex.isEmpty
                  ? null
                  : () {
                      if (isWide) {
                        setState(() {
                          _selectedContact = c;
                          _showMyProfileInRightPane = false;
                        });
                      } else {
                        _openChat(p, c.destHashHex);
                      }
                    },
              leading: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  backgroundImage: c.avatarPath == null ? null : FileImage(File(c.avatarPath!)),
                  child: c.avatarPath == null ? Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase()) : null,
                ),
              ),
              contentPadding: const EdgeInsets.only(top: 2, left: 14, bottom: 2),
              title: Text(c.name),
              subtitle: Text(c.destHashHex.isEmpty ? '(нет lxmf)' : c.destHashHex),
              trailing: const Padding(
                padding: EdgeInsets.only(right: 24),
                child: Icon(Icons.chevron_right, size: 22),
              ),
              enabled: c.destHashHex.isNotEmpty,
            ),
        ],
      ),
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
        final isWide = w >= _splitThreshold && _canSplit(w);
        if (!isWide) {
          return Scaffold(
            appBar: AppBar(
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
            ),
            body: _buildContactsList(p, isWide: false),
          );
        }

        final clampedLeft = _masterWidthFor(w);
        return Row(
          children: [
            SizedBox(
              width: clampedLeft,
              child: Scaffold(
                body: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      if (_me != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 28),
                          child: InkWell(
                            onTap: _openMyProfile,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor:
                                        Theme.of(context).colorScheme.surfaceContainerHighest,
                                    backgroundImage: _me!.avatarPath == null
                                        ? null
                                        : FileImage(File(_me!.avatarPath!)),
                                    child: _me!.avatarPath == null
                                        ? Text(_me!.name.isEmpty ? '?' : _me!.name[0].toUpperCase())
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _me!.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                  ),
                                ],
                              ),
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
                              context: context,
                              hintText: 'Search',
                              onClear: _contactsQuery.isEmpty ? null : () => setState(() => _contactsQuery = ''),
                              showClear: _contactsQuery.isNotEmpty,
                            ),
                            onChanged: (v) => setState(() => _contactsQuery = v),
                          ),
                        ),
                      ),
                      Divider(height: 1, color: _dividerColor(context), indent: 12, endIndent: 12),
                      Expanded(child: _buildContactsList(p, isWide: true)),
                    ],
                  ),
                ),
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: _dividerColor(context)),
            Expanded(
              child: _showMyProfileInRightPane && _me != null
                  ? ProfilePage(
                      contactDirPath: _me!.dirPath,
                      displayName: _me!.name,
                      lxmfId: _me!.destHashHex,
                      avatarPath: _me!.avatarPath,
                      onClose: () => setState(() => _showMyProfileInRightPane = false),
                      onApplied: () async {
                        setState(() => _showMyProfileInRightPane = false);
                        await _refresh();
                      },
                    )
                  : Scaffold(
                      appBar: AppBar(
                        elevation: 0,
                        title: _selectedContact == null
                            ? const Text('')
                            : TextField(
                                decoration: _searchDecoration(
                                  context: context,
                                  hintText: 'Search in chat',
                                  onClear: _chatQuery.isEmpty ? null : () => setState(() => _chatQuery = ''),
                                  showClear: false,
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                                onChanged: (v) => setState(() => _chatQuery = v),
                              ),
                        actions: [
                          IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: (_selectedContact == null || _chatQuery.isEmpty)
                                ? null
                                : () => setState(() => _chatQuery = ''),
                          ),
                        ],
                      ),
                      body: _selectedContact == null
                          ? const SizedBox.shrink()
                          : ChatView(
                              paths: p,
                              destHashHex: _selectedContact!.destHashHex,
                              query: _chatQuery,
                            ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ContactsSearchDelegate extends SearchDelegate<ChatContact?> {
  _ContactsSearchDelegate(this.contacts);

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

  List<ChatContact> _filter() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return contacts;
    return contacts
        .where(
          (c) => c.name.toLowerCase().contains(q) || c.destHashHex.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

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
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            backgroundImage: c.avatarPath == null ? null : FileImage(File(c.avatarPath!)),
            child: c.avatarPath == null ? Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase()) : null,
          ),
          title: Text(c.name),
          subtitle: Text(c.destHashHex.isEmpty ? '(нет lxmf)' : c.destHashHex),
          enabled: c.destHashHex.isNotEmpty,
          onTap: c.destHashHex.isEmpty ? null : () => close(context, c),
        );
      },
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.paths, required this.destHashHex});

  final RuncorePaths paths;
  final String destHashHex;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.destHashHex),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: ChatView(paths: widget.paths, destHashHex: widget.destHashHex, query: ''),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.paths,
    required this.destHashHex,
    required this.query,
  });

  final RuncorePaths paths;
  final String destHashHex;
  final String query;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  static const _uuid = Uuid();
  static const _meId = 'me';

  late final User _me;
  late final User _peer;
  late final InMemoryChatController _chatController;
  List<String> _lastMessageIds = const [];

  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _me = const User(id: _meId, name: 'Я');
    _peer = User(id: widget.destHashHex, name: widget.destHashHex);
    _chatController = InMemoryChatController(messages: const []);
    _reload();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) => _reload());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  static final _tsRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2})꞉(\d{2})');

  DateTime _guessCreatedAt(String fileName) {
    final m = _tsRe.firstMatch(fileName);
    if (m != null) {
      final y = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final d = int.parse(m.group(3)!);
      final h = int.parse(m.group(4)!);
      final mi = int.parse(m.group(5)!);
      return DateTime(y, mo, d, h, mi);
    }

    if (fileName.contains(' -- ')) {
      final parts = fileName.split(' -- ');
      if (parts.length >= 2) {
        final tail = parts.last;
        final num = int.tryParse(tail.split('.').first.trim());
        if (num != null) return DateTime.fromMillisecondsSinceEpoch(num);
      }
    }

    return DateTime.now();
  }

  bool _isOutboundByName(String fileName) {
    // Outbound files come from send folder and keep " -- " marker.
    // Inbound files are strictly "YYYY-MM-DD HH꞉MM(.txt| <name>)" and don't contain " -- ".
    return fileName.contains(' -- ');
  }

  List<File> _listFiles(String dir) {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) return const [];
      return d
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => !f.path.split(Platform.pathSeparator).last.startsWith('.'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _reload() async {
    final dest = widget.destHashHex;
    final p = widget.paths;
    final q = widget.query.trim().toLowerCase();

    final deliveredDir = '${p.messagesDir}${Platform.pathSeparator}$dest';
    final sendDir = '${p.sendDir}${Platform.pathSeparator}$dest';
    final pendingDir = '${p.sendDir}${Platform.pathSeparator}.pending${Platform.pathSeparator}$dest';

    final files = <File>[
      ..._listFiles(deliveredDir),
      ..._listFiles(sendDir),
      ..._listFiles(pendingDir),
    ];

    final next = <Message>[];
    for (final f in files) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (name.toLowerCase() == 'caption.txt') continue;

      final createdAt = _guessCreatedAt(name);
      final isPending = f.path.startsWith(sendDir) || f.path.startsWith(pendingDir);
      final outbound = _isOutboundByName(name) || isPending;
      final authorId = outbound ? _meId : _peer.id;

      final ext = name.toLowerCase().split('.').last;
      if (ext == 'txt') {
        final text = await f.readAsString().catchError((_) => '');
        if (q.isNotEmpty && !text.toLowerCase().contains(q) && !name.toLowerCase().contains(q)) {
          continue;
        }
        next.add(
          Message.text(
            id: f.path,
            authorId: authorId,
            createdAt: createdAt,
            text: text.trim(),
            status: isPending ? MessageStatus.sending : null,
          ),
        );
        continue;
      }

      int? size;
      try {
        size = (await f.stat()).size;
      } catch (_) {}
      if (q.isNotEmpty && !name.toLowerCase().contains(q)) {
        continue;
      }
      next.add(
        Message.file(
          id: f.path,
          authorId: authorId,
          createdAt: createdAt,
          name: name,
          size: size,
          source: f.path,
          status: isPending ? MessageStatus.sending : (outbound ? MessageStatus.sent : null),
        ),
      );
    }

    next.sort((a, b) {
      final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final c = at.compareTo(bt);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });

    final nextIds = next.map((m) => m.id).toList(growable: false);
    if (_lastMessageIds.length == nextIds.length) {
      var same = true;
      for (var i = 0; i < nextIds.length; i++) {
        if (_lastMessageIds[i] != nextIds[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _lastMessageIds = nextIds;

    if (!mounted) return;
    await _chatController.setMessages(next, animated: false);
  }

  Future<void> _sendText(String text) async {
    final dest = widget.destHashHex.trim().toLowerCase();
    if (dest.isEmpty) return;

    final root = widget.paths.sendDir;
    final dir = Directory('$root${Platform.pathSeparator}$dest');
    await dir.create(recursive: true);

    final fileName = 'msg -- ${_uuid.v4()}.txt';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(text, flush: true);

    await _reload();
  }

  Future<User?> _resolveUser(String id) async {
    if (id == _me.id) return _me;
    if (id == _peer.id) return _peer;
    return User(id: id, name: id);
  }

  @override
  Widget build(BuildContext context) {
    return Chat(
      currentUserId: _me.id,
      resolveUser: _resolveUser,
      chatController: _chatController,
      onMessageSend: _sendText,
      theme: ChatTheme.fromThemeData(Theme.of(context)),
    );
  }
}
