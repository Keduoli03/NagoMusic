import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_log.dart';

/// 把 Flutter 三条未捕获异常通道接进 [AppLog]。
///
/// 在这之前项目里一条全局异常处理都没有（`FlutterError.onError`、
/// `PlatformDispatcher.onError`、`runZonedGuarded` 全部缺席），异常只会打在
/// 控制台上——而用户手上的 release 包没有控制台。这是「日志没有用」最直接的
/// 原因：真正出问题的时候什么都没留下。
///
/// 三条通道各管一段，缺一不可：
/// - [FlutterError.onError]：build / layout / paint 期间的同步异常。
/// - [PlatformDispatcher.instance.onError]：没有 zone 兜住的异步异常。
/// - [runGuardedApp] 的 `runZonedGuarded`：App 自己代码里逃逸的异步异常。
void installErrorHandlers() {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLog.instance.e(
      'Flutter',
      details.summary.toString(),
      details.exception,
      details.stack,
    );
    // 保留原行为：debug 下照样把红屏错误打出来。
    previousFlutterError?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLog.instance.e('Platform', '未捕获的异步异常', error, stack);
    // 返回 true = 已处理。一个音乐播放器不该因为某个后台 Future 抛了异常就整个
    // 挂掉；现在异常已经落盘，事后查得到。
    return true;
  };
}

/// 在 zone 里启动 App，捕获逃出所有 try/catch 的异步异常。
///
/// `WidgetsFlutterBinding.ensureInitialized()` 必须在这个 zone **内部**调用，
/// 否则 binding 绑在根 zone 上，`runZonedGuarded` 捕获不到 framework 抛出的
/// 异步异常。所以 binding 的初始化放在 [body] 里，不要提到外面。
Future<void> runGuardedApp(FutureOr<void> Function() body) async {
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      installErrorHandlers();
      try {
        await body();
      } finally {
        if (!done.isCompleted) done.complete();
      }
    },
    (Object error, StackTrace stack) {
      AppLog.instance.e('Zone', '未捕获的异常', error, stack);
      unawaited(AppLog.instance.flush());
      if (!done.isCompleted) done.complete();
    },
  );
  return done.future;
}
