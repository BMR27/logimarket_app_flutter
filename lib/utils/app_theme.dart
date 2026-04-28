import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF1565C0);      // Azul principal
  static const Color primaryLight = Color(0xFF5E92F3);
  static const Color accent = Color(0xFFFF6F00);        // Naranja
  static const Color success = Color(0xFF2E7D32);       // Verde
  static const Color error = Color(0xFFC62828);         // Rojo
  static const Color warning = Color(0xFFF57F17);       // Amarillo

  // Estados de mochila
  static const Color statusAsignada = Color(0xFF1565C0);
  static const Color statusEnRuta = Color(0xFFE65100);
  static const Color statusTerminada = Color(0xFF2E7D32);
  static const Color statusCancelada = Color(0xFFC62828);

  static Color forBackpackState(int state) {
    switch (state) {
      case 1: return statusAsignada;
      case 2: return statusEnRuta;
      case 3: return statusTerminada;
      case 4: return statusCancelada;
      default: return Colors.grey;
    }
  }
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            minimumSize: Size(double.infinity, 48),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          filled: true,
          fillColor: Color(0xFFF5F5F5),
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      );
}
