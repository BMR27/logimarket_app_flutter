import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../providers/orders_provider.dart';
import '../../providers/map_navigation_provider.dart';
import '../../models/order_model.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _followUser = true;
  Set<Marker> _markers = {};
  bool _routeAnimated = false;
  bool _locationCentered = false; // Para centrar solo la primera vez al arrancar

  static const _initialCamera = CameraPosition(
    target: LatLng(19.432608, -99.133209),
    zoom: 5,
  );

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      // Obtener posición inmediata para centrar el mapa sin esperar el stream
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 10));
        if (mounted) setState(() => _currentPosition = pos);
        if (_mapController != null && !_locationCentered) {
          _locationCentered = true;
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(pos.latitude, pos.longitude),
                zoom: 15,
              ),
            ),
          );
        }
      } catch (_) {
        // Si falla el fix rápido, el stream lo manejará
      }
      _startLocationUpdates();
    }
  }

  void _startLocationUpdates() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _currentPosition = pos);

      final mapNav = context.read<MapNavigationProvider>();

      // Primera posición real de GPS: centrar cámara en el usuario
      if (!_locationCentered) {
        if (_mapController != null) {
          // Mapa ya listo → centrar ahora
          _locationCentered = true;
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(pos.latitude, pos.longitude),
                zoom: 15,
              ),
            ),
          );
        }
        // Si _mapController aún es null, onMapCreated lo hará
        return;
      }

      // Solo seguir con cámara inclinada si el viaje fue iniciado
      if (mapNav.destination != null && mapNav.started && _mapController != null) {
        _animateNavCamera(pos, mapNav.destination!);
      } else if (_followUser && _mapController != null && mapNav.destination == null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        );
      }
    });
  }

  void _animateNavCamera(Position pos, LatLng destination) {
    final bearing = _bearing(
      pos.latitude, pos.longitude,
      destination.latitude, destination.longitude,
    );
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 16.5,
          tilt: 50,
          bearing: bearing,
        ),
      ),
    );
  }

  Future<void> _zoomToUserOnTripStart(LatLng? destination) async {
    if (_mapController == null) return;

    Position? pos = _currentPosition;

    // Intenta refrescar ubicación para centrar con la posición más actual.
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));
      if (mounted) {
        setState(() => _currentPosition = pos);
      }
    } catch (_) {
      // Si falla el fix inmediato, usa la última posición disponible.
    }

    if (pos == null) return;

    if (destination != null) {
      _animateNavCamera(pos, destination);
      return;
    }

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 17,
        ),
      ),
    );
  }

  double _bearing(double lat1, double lng1, double lat2, double lng2) {
    final la1 = lat1 * pi / 180;
    final la2 = lat2 * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final y = sin(dLng) * cos(la2);
    final x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  void _buildMarkers(List<OrderModel> orders, LatLng? destination) {
    _markers = orders
        .where((o) => o.latitud != null && o.longitud != null)
        .map((o) {
      final lat = double.tryParse(o.latitud!);
      final lng = double.tryParse(o.longitud!);
      if (lat == null || lng == null) return null;
      return Marker(
        markerId: MarkerId('order_${o.id}'),
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(
          title: o.folioOrdenCliente,
          snippet: o.cliente,
        ),
      );
    })
        .whereType<Marker>()
        .toSet();

    if (destination != null) {
      _markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destino'),
        zIndex: 2,
      ));
    }
  }

  void _animateToBounds(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersProvider>().orders;
    final mapNav = context.watch<MapNavigationProvider>();
    final isNavigating = mapNav.destination != null;

    _buildMarkers(orders, mapNav.destination);

    // Cuando llega la ruta, mostrar bounds (vista previa)
    if (mapNav.routePoints.isNotEmpty && !_routeAnimated) {
      _routeAnimated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _animateToBounds(mapNav.routePoints);
      });
    }
    if (!isNavigating) _routeAnimated = false;

    final polylines = mapNav.routePoints.isNotEmpty
        ? <Polyline>{
            Polyline(
              polylineId: const PolylineId('route'),
              points: mapNav.routePoints,
              color: const Color(0xFF1A73E8),
              width: 7,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
          }
        : <Polyline>{};

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _initialCamera,
          markers: _markers,
          polylines: polylines,
          myLocationEnabled: _currentPosition != null,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: isNavigating,
          tiltGesturesEnabled: true,
          onMapCreated: (c) {
            _mapController = c;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_locationCentered && _currentPosition != null) {
                // GPS ya llegó antes de que el mapa estuviera listo → centrar ahora
                _locationCentered = true;
                _mapController?.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude),
                      zoom: 15,
                    ),
                  ),
                );
              } else if (mapNav.routePoints.isNotEmpty) {
                _animateToBounds(mapNav.routePoints);
              }
            });
          },
        ),

        // --- Calculando ruta ---
        if (mapNav.loading)
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 2))
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Color(0xFF1A73E8)),
                    ),
                    SizedBox(width: 10),
                    Text('Calculando ruta...',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),

        // --- Panel de navegación inferior (estilo Google Maps) ---
        if (isNavigating && !mapNav.loading)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _NavigationPanel(
              mapNav: mapNav,
              onStart: () {
                context.read<MapNavigationProvider>().startNavigation();
                _zoomToUserOnTripStart(mapNav.destination);
              },
              onStop: () => context.read<MapNavigationProvider>().clearRoute(),
              onRecenter: () {
                if (_currentPosition != null) {
                  _animateNavCamera(_currentPosition!, mapNav.destination!);
                }
              },
            ),
          ),

        // --- Botón centrar usuario (solo sin navegación) ---
        if (!isNavigating)
          Positioned(
            bottom: 24,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'follow_btn',
              backgroundColor:
                  _followUser ? const Color(0xFF1A73E8) : Colors.white,
              elevation: 4,
              onPressed: () {
                setState(() => _followUser = !_followUser);
                if (_currentPosition != null) {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude)),
                  );
                }
              },
              child: Icon(
                _followUser ? Icons.near_me : Icons.near_me_outlined,
                color:
                    _followUser ? Colors.white : const Color(0xFF1A73E8),
              ),
            ),
          ),

        // --- Contador de pedidos en mapa ---
        if (!isNavigating)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4)
                ],
              ),
              child: Text(
                '${_markers.length} en mapa',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Panel inferior de navegación ───────────────────────────────────────────

class _NavigationPanel extends StatelessWidget {
  final MapNavigationProvider mapNav;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRecenter;

  const _NavigationPanel({
    required this.mapNav,
    required this.onStart,
    required this.onStop,
    required this.onRecenter,
  });

  @override
  Widget build(BuildContext context) {
    final address = mapNav.destinationAddress ?? 'Destino';
    final hasRoute = mapNav.distanceText.isNotEmpty;
    final isStarted = mapNav.started;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black26,
              blurRadius: 16,
              offset: Offset(0, -3))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Ícono + dirección
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isStarted
                          ? const Color(0xFF1A73E8)
                          : const Color(0xFF34A853),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isStarted ? Icons.navigation : Icons.route,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isStarted ? 'Navegando a' : 'Ruta calculada',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Botón recentrar (solo cuando navegando)
                  if (isStarted)
                    IconButton(
                      onPressed: onRecenter,
                      icon: const Icon(Icons.my_location,
                          color: Color(0xFF1A73E8)),
                      tooltip: 'Recentrar',
                    ),
                ],
              ),

              // Distancia y duración
              if (hasRoute) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Chip(
                      icon: Icons.route_outlined,
                      text: mapNav.distanceText,
                      bgColor: const Color(0xFFE8F0FE),
                      textColor: const Color(0xFF1A73E8),
                    ),
                    const SizedBox(width: 10),
                    _Chip(
                      icon: Icons.access_time_outlined,
                      text: mapNav.durationText,
                      bgColor: const Color(0xFFE6F4EA),
                      textColor: const Color(0xFF34A853),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 14),

              if (!isStarted) ...[
                // Botón INICIAR VIAJE
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.navigation, size: 20),
                    label: const Text('Iniciar viaje',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF34A853),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Botón cancelar (secundario)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: onStop,
                    child: const Text('Cancelar',
                        style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ),
                ),
              ] else ...[
                // Botón FINALIZAR VIAJE
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                    label: const Text('Finalizar viaje',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEA4335),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color bgColor;
  final Color textColor;

  const _Chip({
    required this.icon,
    required this.text,
    required this.bgColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

