import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/login/login_screen.dart';
import '../screens/main/main_screen.dart';
import '../screens/welcome/welcome_screen.dart';

/// Maneja la navegación post-splash entre bienvenida, login y pantalla principal.
class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.state == AuthState.authenticated) {
          return const MainScreen();
        }
        // Mostrar pantalla de bienvenida cuando no está autenticado
        return const WelcomeScreen();
      },
    );
  }
}
