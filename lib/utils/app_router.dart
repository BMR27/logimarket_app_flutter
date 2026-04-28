import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/login/login_screen.dart';
import '../screens/main/main_screen.dart';

/// Maneja la navegación post-splash entre login y pantalla principal.
class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.state == AuthState.authenticated) {
          return const MainScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
