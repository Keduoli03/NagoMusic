import 'package:flutter/material.dart';

import '../../app/services/bili/bili_api.dart';
import '../../app/services/bili/bili_models.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../components/index.dart';
import 'bili_playback.dart';

/// B 站搜索页。
///
/// 从 B站主页右上角的搜索按钮推进来 —— 搜索是低频动作，不值得在主页常驻一个
/// 输入框和一个分段切换器。
class BiliSearchPage extends StatefulWidget {
  const BiliSearchPage({super.key});

  @override
  State<BiliSearchPage> createState() => _BiliSearchPageState();
}

class _BiliSearchPageState extends State<BiliSearchPage> {
  final BiliApi _api = BiliApi.instance;
  final TextEditingController _keyword = TextEditingController();
  final FocusNode _focus = FocusNode();

  List<BiliVideo> _results = const [];
  bool _searching = false;
  String _error = '';
  String _lastKeyword = '';

  @override
  void initState() {
    super.initState();
    // 进来就聚焦弹键盘：用户点搜索按钮就是为了打字。
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _keyword.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _keyword.text.trim();
    if (keyword.isEmpty) return;
    _focus.unfocus();
    setState(() {
      _searching = true;
      _error = '';
      _lastKeyword = keyword;
    });
    try {
      final videos = await _api.searchVideos(keyword);
      if (!mounted) return;
      setState(() {
        _results = videos;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e is BiliApiException ? e.message : '搜索失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: const AppTopBar(
        title: '搜索 B站',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _buildInput(context),
          ),
          Expanded(child: _buildBody(bottomPadding)),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final c = AppColors.of(context);
    return TextField(
      controller: _keyword,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(),
      decoration: InputDecoration(
        hintText: '搜索 B 站视频音频',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          tooltip: '搜索',
          icon: const Icon(Icons.arrow_forward_rounded),
          onPressed: _search,
        ),
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          borderSide: BorderSide(color: c.line, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          borderSide: BorderSide(color: c.line, width: 0.5),
        ),
      ),
    );
  }

  Widget _buildBody(double bottomPadding) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return _hint(_error, actionLabel: '重试', onAction: _search);
    }
    if (_results.isEmpty) {
      return _hint(
        _lastKeyword.isEmpty ? '输入关键词，搜索 B 站上的音频' : '没有搜到「$_lastKeyword」相关内容',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(8, 0, 8, bottomPadding),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final video = _results[index];
        return BiliVideoTile(
          video: video,
          onTap: () => BiliPlayback.openVideo(context, video),
        );
      },
    );
  }

  Widget _hint(String message, {String? actionLabel, VoidCallback? onAction}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.of(context).muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
