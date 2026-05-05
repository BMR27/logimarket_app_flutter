import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSoundService {
  static const _uiSoundEnabledKey = 'uiSoundEnabled';
  static const _uiVolumeKey = 'uiVolume';
  static const _codebarSoundEnabledKey = 'codebarSoundEnabled';

  static Future<void> playUiTap() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_uiSoundEnabledKey) ?? true;
    if (!enabled) return;

    // Mantiene lectura de volumen para compatibilidad futura.
    final volume = prefs.getDouble(_uiVolumeKey) ?? 0.7;
    if (volume <= 0) return;

    try {
      await SystemSound.play(SystemSoundType.click);
      await HapticFeedback.selectionClick();
    } catch (_) {
      // Evita romper el flujo de UI si el sistema no soporta sonido.
    }
  }

  static Future<void> playScannerSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_codebarSoundEnabledKey) ?? true;
    if (!enabled) return;

    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Evita romper el flujo de escaneo si el sistema no soporta sonido.
    }
  }
}