import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Servicio singleton que monitorea la conectividad de red.
/// Emite un evento cuando la conexión es RESTAURADA después de haber estado
/// sin internet, para que la app pueda sincronizar cambios pendientes.
class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final _onRestoredController = StreamController<void>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _wasOffline = false;

  /// Stream que emite cuando la conexión es restaurada.
  Stream<void> get onConnectionRestored => _onRestoredController.stream;

  void startMonitoring() {
    _subscription?.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (!isOnline) {
        _wasOffline = true;
        debugPrint('[Connectivity] sin conexión');
      } else if (_wasOffline) {
        _wasOffline = false;
        debugPrint('[Connectivity] conexión restaurada — disparando sync');
        _onRestoredController.add(null);
      }
    });
  }

  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
  }
}
