import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'core/index.dart';
import 'pages/music_home_page.dart';
import 'viewmodels/library_viewmodel.dart';
import 'viewmodels/player_viewmodel.dart';
import 'widgets/mini_player_bar.dart';
import 'widgets/side_menu.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier(_loadThemeMode());
  static final ValueNotifier<bool> dynamicColorNotifier =
      ValueNotifier(_loadDynamicColor());
  
  static final ValueNotifier<double> playerBarBottomPadding = ValueNotifier(60.0);
  static final PlayerBarNavigatorObserver routeObserver = PlayerBarNavigatorObserver();

  static ThemeMode _loadThemeMode() {
    final raw = StorageUtil.getStringOrDefault(
      StorageKeys.themeMode,
      defaultValue: 'system',
    );
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static bool _loadDynamicColor() {
    return StorageUtil.getBoolOrDefault(
      StorageKeys.dynamicColorEnabled,
      defaultValue: false,
    );
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    String value;
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      case ThemeMode.system:
        value = 'system';
        break;
    }
    await StorageUtil.setString(StorageKeys.themeMode, value);
    themeModeNotifier.value = mode;
  }

  static Future<void> setDynamicColorEnabled(bool enabled) async {
    await StorageUtil.setBool(StorageKeys.dynamicColorEnabled, enabled);
    dynamicColorNotifier.value = enabled;
  }

  ThemeData _applyDynamic(ThemeData base, ColorScheme? scheme) {
    if (scheme == null) return base;
    return base.copyWith(
      colorScheme: scheme,
      primaryColor: scheme.primary,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    PlayerViewModel();
    LibraryViewModel();
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, mode, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: dynamicColorNotifier,
              builder: (context, dynamicEnabled, _) {
                final lightTheme = _applyDynamic(
                  AppTheme.light(),
                  dynamicEnabled ? lightDynamic : null,
                );
                final darkTheme = _applyDynamic(
                  AppTheme.dark(),
                  dynamicEnabled ? darkDynamic : null,
                );
                return MaterialApp(
                  navigatorKey: NavigatorUtil.navigatorKey,
                  scaffoldMessengerKey: NavigatorUtil.scaffoldMessengerKey,
                  title: AppConstants.appName,
                  theme: lightTheme,
                  darkTheme: darkTheme,
                  themeMode: mode,
                  home: const MusicHomePage(),
                  routes: AppRoutes.routes,
                  navigatorObservers: [routeObserver],
                  debugShowCheckedModeBanner: false,
                  scrollBehavior: const NoOverscrollBehavior(),
                  builder: (context, child) {
                    final appChild = child ?? const MusicHomePage();
                    return Stack(
                      children: [
                        // 1. Main Content Layer (Slides)
                        Positioned.fill(
                          child: Watch((context) {
                            final isOpen = LibraryViewModel().isMenuOpen.value;
                            final double slideOffset = isOpen ? 280.0 : 0.0;
                            
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              transform: Matrix4.identity()
                                ..translateByDouble(slideOffset, 0, 0, 0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(isOpen ? 20 : 0),
                                child: Stack(
                                  children: [
                                    Container(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                      child: appChild,
                                    ),
                                    if (isOpen)
                                      Positioned.fill(
                                        child: GestureDetector(
                                          onTap: () =>
                                              LibraryViewModel().isMenuOpen.value = false,
                                          behavior: HitTestBehavior.translucent,
                                          child: Container(color: Colors.transparent),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),

                        // 2. Menu Layer (Slides in)
                        Watch((context) {
                          final isOpen = LibraryViewModel().isMenuOpen.value;
                          return AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            top: 0,
                            bottom: 0,
                            left: isOpen ? 0 : -280,
                            width: 280,
                            child: const SideMenu(),
                          );
                        }),

                        // 3. MiniPlayerBar (Fixed at bottom, stays visible)
                        ValueListenableBuilder<double>(
                          valueListenable: playerBarBottomPadding,
                          builder: (context, basePadding, _) {
                            final isOpen = LibraryViewModel().isMenuOpen.value;
                            // If menu is open, force padding to 0 (since navbar hides)
                            // Otherwise use basePadding (which accounts for navbar)
                            final effectiveBasePadding = isOpen ? 0.0 : basePadding;
                            
                            // Add safe area padding to the base padding
                            // If negative (hidden), don't add it
                            final bottomPadding = effectiveBasePadding < 0 
                                ? effectiveBasePadding 
                                : effectiveBasePadding + MediaQuery.of(context).padding.bottom;

                            return AnimatedPositioned(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              left: 0,
                              right: 0,
                              bottom: bottomPadding,
                              child: Watch((context) {
                                // Ensure we listen to the signal for updates
                                // ignore: unused_local_variable
                                final tick = LibraryViewModel().settingsTick.value;

                                if (LibraryViewModel().isGlobalMultiSelectMode) {
                                  return const SizedBox.shrink();
                                }
                                return const SafeArea(
                                  top: false,
                                  child: SizedBox(
                                    height: 72,
                                    child: MiniPlayerBar(),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class PlayerBarNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routeStack = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeStack.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeStack.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _routeStack.remove(oldRoute);
    }
    if (newRoute != null) {
      _routeStack.add(newRoute);
    }
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeStack.remove(route);
    _update();
  }

  void _update() {
    // Determine target padding based on the top-most route
    double targetPadding = 0.0;
    
    if (_routeStack.isNotEmpty) {
      final topRoute = _routeStack.last;
      
      // If the top route is a popup (Dialog, BottomSheet, Menu), hide the bar
      if (topRoute is PopupRoute) {
        targetPadding = -120.0;
      } else {
        // Check route name for specific pages
        final name = topRoute.settings.name;
        if (name == AppRoutes.home) {
          targetPadding = 60.0;
        } else if (name == '/player') {
          targetPadding = -120.0;
        } else {
          // Default for other pages (sub-pages)
          targetPadding = 0.0;
        }
      }
    }
    
    // Update the value
    // Use a microtask to avoid updating during build phase if called synchronously
    Future.microtask(() {
      App.playerBarBottomPadding.value = targetPadding;
    });
  }
}
