import 'dart:async';

import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme/app_icons.dart';
import '../../components/index.dart';

/// B 站扫码登录。
///
/// 简音走的是内嵌 WebView 登录页再截 cookie；Flutter 这边引 webview 要额外的原生
/// 依赖，而扫码接口本身就返回 `Set-Cookie`，同样能拿到 SESSDATA，所以用扫码。
/// 登录成功后 pop 出 [BiliAccount]。
class BiliLoginPage extends StatefulWidget {
  const BiliLoginPage({super.key});

  @override
  State<BiliLoginPage> createState() => _BiliLoginPageState();
}

class _BiliLoginPageState extends State<BiliLoginPage> {
  final BiliApi _api = BiliApi.instance;

  Timer? _pollTimer;
  String? _qrContent;
  String _qrKey = '';
  String _hint = '正在获取二维码…';
  bool _loading = true;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _refreshQrCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshQrCode() async {
    _pollTimer?.cancel();
    setState(() {
      _loading = true;
      _expired = false;
      _qrContent = null;
      _hint = '正在获取二维码…';
    });
    try {
      await _api.ensureBuvid();
      final (content, key) = await _api.generateQrCode();
      if (!mounted) return;
      setState(() {
        _qrContent = content;
        _qrKey = key;
        _loading = false;
        _hint = '请使用哔哩哔哩客户端扫码';
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _expired = true;
        _hint = '获取二维码失败：$e';
      });
    }
  }

  Future<void> _poll() async {
    if (_qrKey.isEmpty) return;
    try {
      final result = await _api.pollQrCode(_qrKey);
      if (!mounted) return;
      switch (result.status) {
        case BiliQrStatus.waiting:
        case BiliQrStatus.scanned:
          setState(() => _hint = result.message);
        case BiliQrStatus.expired:
          _pollTimer?.cancel();
          setState(() {
            _expired = true;
            _hint = result.message;
          });
        case BiliQrStatus.confirmed:
          _pollTimer?.cancel();
          final account = await _api.saveLoginCookies(result.cookies);
          if (!mounted) return;
          AppToast.show(context, '已登录 ${account.uname}');
          Navigator.of(context).pop(account);
      }
    } catch (_) {
      // 单次轮询失败（断网抖动）不打断流程，下一次 tick 再试。
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = _qrContent;
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '登录哔哩哔哩',
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 232,
                height: 232,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: _loading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : content == null
                    ? Icon(AppIcons.error, size: 48, color: scheme.error)
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          QrImageView(
                            data: content,
                            version: QrVersions.auto,
                            size: 200,
                            backgroundColor: Colors.white,
                            // 失效时压暗二维码，视觉上告诉用户「别扫了」。
                            eyeStyle: QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: _expired ? Colors.black26 : Colors.black,
                            ),
                            dataModuleStyle: QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: _expired ? Colors.black26 : Colors.black,
                            ),
                          ),
                          if (_expired)
                            FilledButton.tonal(
                              onPressed: _refreshQrCode,
                              child: const Text('刷新二维码'),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              Text(
                _hint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(
                '登录后可以查看收藏夹，大会员还能拿到 Hi-Res 音源。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
