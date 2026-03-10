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
