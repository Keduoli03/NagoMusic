import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/router/app_router.dart';
import 'side_menu.dart';

class TabletShell extends StatefulWidget {
  final Map<String, WidgetBuilder> routes;
  final String initialRoute;

  const TabletShell({
    super.key,
    required this.routes,
    required this.initialRoute,
  });

  @override
  State<TabletShell> createState() => TabletShellState();
}

class TabletShellState extends State<TabletShell> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String _currentRoute = AppRoutes.home;

  void navigate(String route) {
    if (_currentRoute == route) return;
    _currentRoute = route;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(route, (r) => false);
    });
  }

  void push(String route) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState?.pushNamed(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final drawerWidth = (width * 0.32).clamp(200.0, 260.0);
    return Row(
      children: [
        SizedBox(
          width: drawerWidth,
          child: SideMenu(
            onNavigate: navigate,
            onPush: push,
          ),
        ),
        Expanded(
          child: Navigator(
            key: _navigatorKey,
            initialRoute: widget.initialRoute,
            onGenerateRoute: (settings) {
              final builder = widget.routes[settings.name];
              final target = builder ?? widget.routes[AppRoutes.home]!;
              return MaterialPageRoute(
                builder: target,
                settings: settings,
              );
            },
          ),
        ),
      ],
    );
  }
}
