import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/services/webdav/webdav_music_service.dart';
import '../../../app/services/webdav/webdav_source_repository.dart';
import '../../../components/index.dart';

class WebDavFolderPickerPage extends StatefulWidget {
  final WebDavSource source;
  final String initialPath;
  final List<String> initialSelected;

  const WebDavFolderPickerPage({
    super.key,
    required this.source,
    required this.initialPath,
    this.initialSelected = const [],
  });

  @override
  State<WebDavFolderPickerPage> createState() => _WebDavFolderPickerPageState();
}

class _WebDavFolderPickerPageState extends State<WebDavFolderPickerPage> {
  final WebDavMusicService _service = WebDavMusicService();

  late String _path;
  late final Set<String> _selected;
  bool _loading = true;
  String? _error;
  List<WebDavDirectory> _dirs = const [];

  @override
  void initState() {
    super.initState();
    _path = _normalize(widget.initialPath);
    _selected = widget.initialSelected.map(_normalize).toSet();
    _load();
  }

  String _normalize(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '/';
    t = t.replaceAll('\\', '/');
    if (!t.startsWith('/')) t = '/$t';
    if (t.length > 1 && t.endsWith('/')) t = t.substring(0, t.length - 1);
    return t;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dirs = await _service.listDirectories(source: widget.source, path: _path);
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _enter(WebDavDirectory dir) {
    setState(() {
      _path = _normalize(dir.path);
    });
    _load();
  }

  void _goUp() {
    final ctx = p.url;
    final parent = ctx.dirname(_path);
    if (parent == _path) return;
    setState(() {
      _path = _normalize(parent);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final canGoUp = _path != '/';
    final selectedCount = _selected.length;
    final currentSelected = _selected.contains(_path);
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);

    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: '选择文件夹',
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _loading
                ? null
                : () => Navigator.pop(
                      context,
                      _selected.toList()..sort(),
                    ),
            child: Text('完成($selectedCount)'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          AppSettingSection(
            title: '当前位置',
            children: [
              AppSettingTile(
                title: _path,
                leading: const Icon(Icons.location_on_outlined),
                trailing: Checkbox(
                  value: currentSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(_path);
                      } else {
                        _selected.remove(_path);
                      }
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onTap: () {
                  setState(() {
                    if (currentSelected) {
                      _selected.remove(_path);
                    } else {
                      _selected.add(_path);
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            AppSettingSection(
              title: '加载失败',
              children: [
                AppSettingTile(
                  title: '点击重试',
                  subtitle: _error,
                  leading: const Icon(Icons.error_outline),
                  onTap: _load,
                ),
              ],
            )
          else
            AppSettingSection(
              title: '子文件夹',
              children: [
                if (canGoUp)
                  AppSettingTile(
                    title: '..',
                    leading: const Icon(Icons.drive_folder_upload_outlined),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _goUp,
                  ),
                if (_dirs.isEmpty)
                  const AppSettingTile(
                    title: '（空）',
                    leading: Icon(Icons.folder_off_outlined),
                  )
                else
                  ..._dirs.map(
                    (d) => AppSettingTile(
                      title: d.name,
                      subtitle: d.path,
                      leading: const Icon(Icons.folder_outlined),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _selected.contains(_normalize(d.path)),
                            onChanged: (v) {
                              final normalized = _normalize(d.path);
                              setState(() {
                                if (v == true) {
                                  _selected.add(normalized);
                                } else {
                                  _selected.remove(normalized);
                                }
                              });
                            },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => _enter(d),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
