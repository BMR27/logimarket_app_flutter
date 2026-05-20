import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/orders_provider.dart';
import 'providers/backpacks_provider.dart';
import 'providers/map_navigation_provider.dart';
import 'utils/app_theme.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/login/login_screen.dart';

void main() {
  runApp(const LogimarketApp());
}

class LogimarketApp extends StatelessWidget {
  const LogimarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..checkSession()),
        ChangeNotifierProvider(create: (_) => OrdersProvider()),
        ChangeNotifierProvider(create: (_) => BackpacksProvider()),
        ChangeNotifierProvider(create: (_) => MapNavigationProvider()),
      ],
      child: const _AppLifecycleWrapper(),
    );
  }
}

/// Observa el ciclo de vida para recargar equipos al volver de apps externas (Maps, Waze).
class _AppLifecycleWrapper extends StatefulWidget {
  const _AppLifecycleWrapper();

  @override
  State<_AppLifecycleWrapper> createState() => _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends State<_AppLifecycleWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Al volver de una app externa, recargar equipos si están vacíos
      // sin tocar el estado de autenticación.
      context.read<AuthProvider>().ensureEquiposLoaded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Logimarket',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}
