import 'package:flutter/material.dart';

import '../../models/music_entity.dart';
import '../../viewmodels/library_viewmodel.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_toast.dart';

class WebDavPage extends StatefulWidget {
  final MusicSource? source;
  final bool isAdd;
  const WebDavPage({super.key, this.source, this.isAdd = false});
  @override
  State<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends State<WebDavPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _endpoint = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _path = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  late MusicSource _source;

  @override
  void initState() {
    super.initState();
    final vm = LibraryViewModel();
    _source = widget.source ?? vm.createWebDavDraft();
    _name.text = _source.name;
    _endpoint.text = _source.endpoint ?? '';
    _username.text = _source.username ?? '';
    _password.text = _source.password ?? '';
    _path.text = _source.path ?? '';
  }

  Future<void> _confirmAdd() async {
    final vm = LibraryViewModel();
    final name = _name.text.trim();
    final endpoint = _endpoint.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, '请输入名称', type: ToastType.error);
      return;
    }
    if (endpoint.isEmpty) {
      AppToast.show(context, '请输入服务地址', type: ToastType.error);
      return;
    }
    setState(() => _loading = true);
    try {
      final draft = _source.copyWith(
        name: name,
        endpoint: endpoint,
        username: _username.text.trim(),
        password: _password.text,
      );
      final ok = await vm.testWebDavConnection(draft);
      if (!mounted) return;
      if (!ok) {
        AppToast.show(context, '连接失败，请检查地址或账号密码', type: ToastType.error);
        return;
      }
      await vm.upsertSource(draft);
      _source = draft;
      if (!mounted) return;
      AppToast.show(context, '连接成功，已添加', type: ToastType.success);
      Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    final vm = LibraryViewModel();
    final updated = _source.copyWith(
      name: _name.text.trim().isEmpty ? _source.name : _name.text.trim(),
      endpoint: _endpoint.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
    );
    await vm.upsertSource(updated);
    _source = updated;
  }

  Future<void> _chooseFolder() async {
    if (_endpoint.text.isEmpty) {
      AppToast.show(context, '请输入服务地址', type: ToastType.error);
      return;
    }
    final vm = LibraryViewModel();
    final draft = _source.copyWith(
      endpoint: _endpoint.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      // Pass current paths to dialog so it knows what's selected
      includeFolders: _source.includeFolders,
      path: _source.path,
    );
    
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _DirectoryPickerDialog(source: draft, vm: vm),
    );
    if (!mounted) return;

    if (result != null) {
      setState(() {
        _source = _source.copyWith(
          includeFolders: result,
          path: result.isNotEmpty ? result.first : '',
        );
      });
    }
  }



  void _removeFolder(String path) {
    final folders = List<String>.from(_source.includeFolders);
    folders.remove(path);
    setState(() {
      _source = _source.copyWith(
        includeFolders: folders,
        path: folders.isNotEmpty ? folders.first : '',
      );
    });
  }

  Future<void> _confirmRemoveFolder(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: '移除文件夹',
        contentText: '确认不再扫描该文件夹吗？\n$path',
        confirmText: '移除',
        isDestructive: true,
        onConfirm: () {},
      ),
    );
    if (ok == true) {
      _removeFolder(path);
    }
  }

  Future<void> _confirmDelete() async {
    final vm = LibraryViewModel();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: '删除 WebDAV',
        contentText: '确认删除 ${_source.name.isNotEmpty ? _source.name : 'WebDAV'} 吗？',
        confirmText: '删除',
        isDestructive: true,
        onConfirm: () {},
      ),
    );
    if (ok == true) {
      await vm.removeSource(_source);
      if (!mounted) return;
      AppToast.show(context, '已删除', type: ToastType.success);
      Navigator.pop(context);
    }
  }

  Widget _glow({
    required Alignment alignment,
    required double size,
    required List<Color> colors,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1C1F24),
              Color(0xFF22262C),
              Color(0xFF1B1D22),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF6F7FB),
              Color(0xFFF7F3E8),
              Color(0xFFF1F7F4),
            ],
          );
          
    final cardColor =
        isDark ? const Color(0xFF1F2329) : const Color.fromARGB(242, 255, 255, 255);
    final shadowColor = isDark
        ? const Color.fromARGB(28, 0, 0, 0)
        : const Color.fromARGB(15, 0, 0, 0);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.isAdd ? '添加 WebDAV' : 'WebDAV'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: background),
        child: Stack(
          children: [
            if (!isDark)
              _glow(
                alignment: Alignment.topRight,
                size: 260,
                colors: const [
                  Color(0x66FDE2A7),
                  Color(0x00FDE2A7),
                ],
              ),
            if (!isDark)
              _glow(
                alignment: Alignment.bottomLeft,
                size: 240,
                colors: const [
                  Color(0x66CBE8FF),
                  Color(0x00CBE8FF),
                ],
              ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (widget.isAdd) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '添加您的 WebDAV 服务',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          children: [
                            _input('名称', _name, hint: '自定义名称'),
                            Divider(
                              height: 1, 
                              indent: 16, 
                              endIndent: 16,
                              color: Theme.of(context).dividerColor.withAlpha(26),
                            ),
                            _input('地址', _endpoint, hint: 'https://example.com/dav'),
                            Divider(
                              height: 1, 
                              indent: 16, 
                              endIndent: 16,
                              color: Theme.of(context).dividerColor.withAlpha(26),
                            ),
                            _input('用户名', _username),
                            Divider(
                              height: 1, 
                              indent: 16, 
                              endIndent: 16,
                              color: Theme.of(context).dividerColor.withAlpha(26),
                            ),
                            _input(
                              '密码',
                              _password,
                              obscure: !_showPassword,
                              suffix: IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  _showPassword ? Icons.visibility : Icons.visibility_off,
                                  size: 20,
                                  color: Theme.of(context).hintColor,
                                ),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!widget.isAdd) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 8),
                          child: Text(
                            '添加文件夹',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).brightness == Brightness.dark 
                                  ? Colors.white70 
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            children: [
                              if (_source.includeFolders.isNotEmpty)
                                ..._source.includeFolders.asMap().entries.map((entry) {
                                  final path = entry.value;
                                  
                                  return Column(
                                    children: [
                                      _customListItem(
                                        leading: const Icon(Icons.folder_outlined),
                                        title: Text(path),
                                        trailing: GestureDetector(
                                          onTap: () => _confirmRemoveFolder(path),
                                          child: Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                            color: Theme.of(context).hintColor,
                                          ),
                                        ),
                                      ),
                                      Divider(
                                        height: 1, 
                                        indent: 56, 
                                        endIndent: 16,
                                        color: Theme.of(context).dividerColor.withAlpha(26),
                                      ),
                                    ],
                                  );
                                }),
                              _customListItem(
                                leading: const Icon(Icons.create_new_folder_outlined),
                                title: const Text('选择文件夹'),
                                trailing: Icon(
                                  Icons.chevron_right, 
                                  size: 20, 
                                  color: Theme.of(context).hintColor,
                                ),
                                onTap: _chooseFolder,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
            const SizedBox(height: 20),
            if (widget.isAdd)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _confirmAdd,
                  child: const Text('确定'),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : () async {
                        await _save();
                        if (!context.mounted) return;
                        AppToast.show(context, '已保存', type: ToastType.success);
                      },
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: _loading ? null : _confirmDelete,
                  child: const Text('删除'),
                ),
              ),
            ],
            if (widget.isAdd) ...[
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield, size: 16, color: Colors.green),
                  SizedBox(width: 6),
                  Text(
                    '密码仅保存在本地',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customListItem({
    required Widget leading,
    required Widget title,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 32, 12),
            child: Row(
              children: [
                IconTheme(
                data: IconThemeData(
                  color: Theme.of(context).iconTheme.color,
                  size: 24,
                ),
                child: leading,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyLarge ?? const TextStyle(),
                  child: title,
                ),
              ),
              const SizedBox(width: 16),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _input(
    String label,
    TextEditingController c, {
    bool obscure = false,
    String? hint,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffix,
  }) {
    Widget? effectiveSuffix = suffix;
    if (effectiveSuffix == null && readOnly) {
      effectiveSuffix = Icon(Icons.arrow_forward_ios, size: 16, color: Theme.of(context).hintColor);
    }

    EdgeInsets contentPadding = const EdgeInsets.fromLTRB(16, 12, 24, 12);
    if (effectiveSuffix != null) {
      effectiveSuffix = Padding(
        padding: const EdgeInsets.only(right: 24),
        child: effectiveSuffix,
      );
      contentPadding = const EdgeInsets.fromLTRB(16, 12, 0, 12);
    }

    return TextField(
      controller: c,
      obscureText: obscure,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: InputBorder.none,
        contentPadding: contentPadding,
        suffixIcon: effectiveSuffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}

class _DirectoryPickerDialog extends StatefulWidget {
  final MusicSource source;
  final LibraryViewModel vm;
  const _DirectoryPickerDialog({required this.source, required this.vm});

  @override
  State<_DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<_DirectoryPickerDialog> {
  List<WebDavEntry> _entries = [];
  bool _loading = true;
  String _currentPath = '';
  String? _error;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _selectedPaths.addAll(widget.source.includeFolders);
    if (_selectedPaths.isEmpty && widget.source.path != null && widget.source.path!.isNotEmpty) {
      _selectedPaths.add(widget.source.path!);
    }
    _load('');
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // path is relative to endpoint.
      final entries = await widget.vm.listWebDavContents(widget.source, path: path);
      if (!mounted) return;
      setState(() {
        _entries = entries.where((e) => e.isCollection).toList();
        _currentPath = path;
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

  String _getRelativePath(String href) {
    try {
      final endpoint = widget.source.endpoint!;
      final uri = Uri.parse(endpoint);
      final endpointPath = uri.path; 
      
      var h = href;
      var ep = endpointPath;
      
      if (ep.endsWith('/')) ep = ep.substring(0, ep.length - 1);
      
      if (h.startsWith(ep)) {
        h = h.substring(ep.length);
      }
      
      if (!h.startsWith('/')) h = '/$h';
      if (h.endsWith('/') && h.length > 1) h = h.substring(0, h.length - 1);
      
      return h;
    } catch (_) {
      return href;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          AppBar(
            title: const Text('选择文件夹'),
            automaticallyImplyLeading: false,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, _selectedPaths.toList()),
                child: const Text('确认'),
              ),
            ],
          ),
          if (_currentPath.isNotEmpty && _currentPath != '/')
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('..'),
              onTap: () {
                final parts = _currentPath.split('/');
                if (parts.isNotEmpty) parts.removeLast();
                var parent = parts.join('/');
                if (parent.isEmpty) parent = '/';
                _load(parent);
              },
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final e = _entries[index];
                          final relPath = _getRelativePath(e.href);
                          final isSelected = _selectedPaths.contains(relPath);
                          
                          return ListTile(
                            leading: const Icon(Icons.folder),
                            title: Text(e.name),
                            subtitle: Text(relPath),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedPaths.add(relPath);
                                  } else {
                                    _selectedPaths.remove(relPath);
                                  }
                                });
                              },
                            ),
                            onTap: () {
                              _load(relPath);
                            },
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('当前路径: $_currentPath\n已选: ${_selectedPaths.length} 个文件夹'),
          ),
        ],
      ),
    );
  }
}
