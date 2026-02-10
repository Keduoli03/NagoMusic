class FolderInfo {
  final String id;
  final String name;
  final int count;
  final bool isSystem;

  const FolderInfo({
    required this.id,
    required this.name,
    required this.count,
    this.isSystem = false,
  });
}
