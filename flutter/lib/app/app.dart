import 'package:flutter/material.dart';

import '../features/contacts/presentation/chats_page.dart';

class RuncoreApp extends StatelessWidget {
  const RuncoreApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brightness,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    final bg = brightness == Brightness.dark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);
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
      dividerTheme: const DividerThemeData(
        color: Color(0x0A000000),
        thickness: 1,
        space: 1,
      ),
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
        const uiTextScale = 0.92;
        return MediaQuery(
          data: media.copyWith(
            textScaler: const TextScaler.linear(uiTextScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const ChatsPage(),
    );
  }
}
