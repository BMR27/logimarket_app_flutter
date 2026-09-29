import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart' as nav;
import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart';

/// Navegación paso a paso dentro de la app con Google Navigation SDK (voz, carriles,
/// rerruteo y tráfico), como la de un conductor de Uber. Si el SDK no está disponible
/// (sin habilitar en Google Cloud, sin términos aceptados, etc.) se ofrece abrir
/// Google Maps o Waze, como antes.
class TurnByTurnScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final String titulo;

  const TurnByTurnScreen({super.key, required this.lat, required this.lng, required this.titulo});

  @override
  State<TurnByTurnScreen> createState() => _TurnByTurnScreenState();
}

class _TurnByTurnScreenState extends State<TurnByTurnScreen> {
  bool _sesionLista = false;
  bool _guiando = false;
  String? _error;
  StreamSubscription<nav.OnArrivalEvent>? _llegada;
  StreamSubscription<nav.RoadSnappedLocationUpdatedEvent>? _ubicacion;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      if (!await nav.GoogleMapsNavigator.areTermsAccepted()) {
        final ok = await nav.GoogleMapsNavigator.showTermsAndConditionsDialog('Navegación', 'Logimarket');
        if (!ok) {
          _fallar('Para navegar dentro de la app hay que aceptar los términos de Google.');
          return;
        }
      }
      await nav.GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: nav.TaskRemovedBehavior.quitService,
      );
      if (!mounted) return;
      setState(() => _sesionLista = true);

      // La ruta solo se calcula cuando el SDK ya tiene ubicación del mensajero
      final hayUbicacion = Completer<void>();
      _ubicacion = await nav.GoogleMapsNavigator.setRoadSnappedLocationUpdatedListener((_) {
        if (!hayUbicacion.isCompleted) hayUbicacion.complete();
      });
      await hayUbicacion.future.timeout(const Duration(seconds: 15), onTimeout: () {});

      final status = await nav.GoogleMapsNavigator.setDestinations(nav.Destinations(
        waypoints: [
          nav.NavigationWaypoint.withLatLngTarget(
            title: widget.titulo,
            target: nav.LatLng(latitude: widget.lat, longitude: widget.lng),
          ),
        ],
        displayOptions: nav.NavigationDisplayOptions(showDestinationMarkers: true),
      ));
      if (status != nav.NavigationRouteStatus.statusOk) {
        _fallar(_mensajeRuta(status));
        return;
      }
      _llegada = nav.GoogleMapsNavigator.setOnArrivalListener((_) => _alLlegar());
      await nav.GoogleMapsNavigator.startGuidance();
      if (mounted) setState(() => _guiando = true);
    } catch (e) {
      _fallar('No se pudo iniciar la navegación en la app ($e).');
    }
  }

  String _mensajeRuta(nav.NavigationRouteStatus s) {
    switch (s) {
      case nav.NavigationRouteStatus.apiKeyNotAuthorized:
        return 'La clave de Google no tiene habilitado el Navigation SDK.';
      case nav.NavigationRouteStatus.quotaExceeded:
        return 'Se agotó la cuota de navegación de Google.';
      case nav.NavigationRouteStatus.locationUnavailable:
        return 'No se obtuvo tu ubicación GPS. Revisa que esté activada.';
      case nav.NavigationRouteStatus.routeNotFound:
        return 'No hay ruta en auto hacia ese destino.';
      case nav.NavigationRouteStatus.networkError:
        return 'Sin conexión para calcular la ruta.';
      default:
        return 'No se pudo calcular la ruta ($s).';
    }
  }

  void _fallar(String msg) {
    if (mounted) setState(() => _error = msg);
  }

  Future<void> _alLlegar() async {
    await nav.GoogleMapsNavigator.stopGuidance();
    if (!mounted) return;
    setState(() => _guiando = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Llegaste al destino'),
        content: Text(widget.titulo),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Aceptar'))],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _abrirExterno({required bool waze}) async {
    final uri = waze
        ? Uri.parse('https://waze.com/ul?ll=${widget.lat},${widget.lng}&navigate=yes')
        : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${widget.lat},${widget.lng}&travelmode=driving');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _llegada?.cancel();
    _ubicacion?.cancel();
    if (_sesionLista) {
      nav.GoogleMapsNavigator.stopGuidance().catchError((_) {});
      nav.GoogleMapsNavigator.cleanup().catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_guiando)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Terminar', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.navigation_outlined, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      icon: const Icon(Icons.map),
                      label: const Text('Abrir en Google Maps'),
                      onPressed: () => _abrirExterno(waze: false),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.directions_car),
                      label: const Text('Abrir en Waze'),
                      onPressed: () => _abrirExterno(waze: true),
                    ),
                  ],
                ),
              ),
            )
          : !_sesionLista
              ? const Center(child: CircularProgressIndicator())
              : nav.GoogleMapsNavigationView(
                  mapId: ApiConfig.mapsMapId.isEmpty ? null : ApiConfig.mapsMapId,
                  initialNavigationUIEnabledPreference: nav.NavigationUIEnabledPreference.automatic,
                  onViewCreated: (c) => c.setMyLocationEnabled(true),
                ),
    );
  }
}
