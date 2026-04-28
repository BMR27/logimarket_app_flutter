import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/orders_provider.dart';
import 'providers/backpacks_provider.dart';
import 'providers/map_navigation_provider.dart';
import 'utils/app_theme.dart';
import 'screens/splash/splash_screen.dart';

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
      child: MaterialApp(
        title: 'Logimarket',
        theme: AppTheme.theme,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
      ),
    );
  }
}
