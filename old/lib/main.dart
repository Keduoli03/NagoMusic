import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'package:just_audio_background/just_audio_background.dart';
import 'app.dart';
import 'core/index.dart';
import 'services/app_audio_service.dart';


final ValueNotifier<String?> bootstrapError = ValueNotifier(null);

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    _installErrorHandlers();
    runApp(const BootstrapApp());
  }, (error, stackTrace) {
    _setBootstrapError(error, stackTrace);
  });
}

void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    _setBootstrapError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _setBootstrapError(error, stack);
    return true;
  };
  ErrorWidget.builder = (details) {
    return _BootstrapErrorScreen(details.exceptionAsString());
  };
}

void _setBootstrapError(Object error, [StackTrace? stackTrace]) {
  if (kDebugMode) {
    debugPrint('Bootstrap error: $error');
    if (stackTrace != null) {
      debugPrint('$stackTrace');
    }
  }
  bootstrapError.value = error.toString();
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await AppInitializer.init(useMockData: kIsWeb);
      await AppAudioService.init();
    } catch (e, stackTrace) {
      _setBootstrapError(e, stackTrace);
      _error = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: bootstrapError,
      builder: (context, error, _) {
        if (error != null || _error != null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '初始化失败\n${error ?? _error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }
        if (_ready) {
          return const App();
        }
        return const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在初始化'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  final String message;
  const _BootstrapErrorScreen(this.message);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }
}
