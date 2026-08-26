import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';
import 'package:path/path.dart' as p;

import '../../../app/services/log/log.dart';
import '../../../app/services/webdav/webdav_music_service.dart';
import '../../../app/services/webdav/webdav_source_repository.dart';
import '../../../components/index.dart';

class WebDavFolderPickerPage extends StatefulWidget {
  final WebDavSource source;
  final String initialPath;
  final List<String> initialSelected;

  /// When true the picker selects a single folder: tap rows to navigate, then
  /// confirm the current location. Returns a one-element list with that path.
  final bool singleSelect;

  /// Verb on the confirm button. The add flow lands here right after saving,
  /// where the action reads as 「导入」 rather than 「完成」.
  final String confirmLabel;

  const WebDavFolderPickerPage({
    super.key,
    required this.source,
    required this.initialPath,
    this.initialSelected = const [],
    this.singleSelect = false,
    this.confirmLabel = '完成',
  });

  @override
  State<WebDavFolderPickerPage> createState() => _WebDavFolderPickerPageState();
}

class _WebDavFolderPickerPageState extends State<WebDavFolderPickerPage> {
  static const String _logTag = 'WebDavFolderPickerPage';

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
      final dirs = await _service.listDirectories(
        source: widget.source,
        path: _path,
      );
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loading = false;
      });
    } catch (e, s) {
      AppLog.instance.w(_logTag, '加载WebDAV目录列表失败，path=$_path', e, s);
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
    final single = widget.singleSelect;
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
                    single ? [_path] : (_selected.toList()..sort()),
                  ),
            child: Text(
              single
                  ? '选择此处'
                  : selectedCount > 0
                  ? '${widget.confirmLabel}($selectedCount)'
                  : widget.confirmLabel,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          if (!single && selectedCount == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
              child: Text(
                '不勾选任何文件夹就直接${widget.confirmLabel}的话，会扫描整个根目录。',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          AppSettingSection(
            title: '当前位置',
            children: [
              AppSettingTile(
                title: _path,
                leading: const Icon(AppIcons.mapPin),
                trailing: single
                    ? null
                    : Checkbox(
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
                onTap: single
                    ? null
                    : () {
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
                  leading: const Icon(AppIcons.error),
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
                    leading: const Icon(AppIcons.folderAdd),
                    trailing: const Icon(AppIcons.chevronRight),
                    onTap: _goUp,
                  ),
                if (_dirs.isEmpty)
                  const AppSettingTile(
                    title: '（空）',
                    leading: Icon(AppIcons.folderOff),
                  )
                else
                  ..._dirs.map(
                    (d) => AppSettingTile(
                      title: d.name,
                      subtitle: d.path,
                      leading: const Icon(AppIcons.folder),
                      trailing: single
                          ? const Icon(AppIcons.chevronRight)
                          : Row(
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
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                const Icon(AppIcons.chevronRight),
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
