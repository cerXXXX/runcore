import 'package:flutter/material.dart';

import '../../../core/platform/runcore_channel.dart';
import 'chat_view.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.paths, required this.destHashHex});

  final RuncorePaths paths;
  final String destHashHex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(destHashHex),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: ChatView(paths: paths, destHashHex: destHashHex, query: ''),
    );
  }
}
