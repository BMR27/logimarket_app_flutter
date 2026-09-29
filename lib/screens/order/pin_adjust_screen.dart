import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../config/api_config.dart';
import '../../services/geo_service.dart';
import '../../services/orders_service.dart';

/// Ajustar el punto exacto de entrega de una orden, al estilo Uber: el mapa se mueve
/// debajo de un pin fijo al centro. Se puede buscar la dirección (Google Places) o
/// arrastrar el mapa hasta la puerta. Al confirmar se guarda como punto 'manual',
/// que el servidor nunca sustituye por uno automático.
class PinAdjustScreen extends StatefulWidget {
  final int orderId;
  final String folio;
  final String direccion;
  final LatLng? inicial;

  const PinAdjustScreen({
    super.key,
    required this.orderId,
    required this.folio,
    required this.direccion,
    this.inicial,
  });

  @override
  State<PinAdjustScreen> createState() => _PinAdjustScreenState();
}

class _PinAdjustScreenState extends State<PinAdjustScreen> {
  final _geo = GeoService();
  final _orders = OrdersService();
  final _busqueda = TextEditingController();
  GoogleMapController? _map;
  late LatLng _centro;
  String? _direccionPin;
  String? _placeId;
  bool _cargandoDireccion = false;
  bool _guardando = false;
  bool _moviendo = false;
  List<SugerenciaDireccion> _sugerencias = const [];
  String _tokenSesion = GeoService.nuevoTokenSesion();
  Timer? _debounceBusqueda;
  Timer? _debounceReverse;

  static const _cdmx = LatLng(19.432608, -99.133209);

  @override
  void initState() {
    super.initState();
    _centro = widget.inicial ?? _cdmx;
    if (widget.inicial == null) _usarMiUbicacion(silencioso: true);
    _actualizarDireccion();
  }

  @override
  void dispose() {
    _debounceBusqueda?.cancel();
    _debounceReverse?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _usarMiUbicacion({bool silencioso = false}) async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 8));
      _moverA(LatLng(pos.latitude, pos.longitude), zoom: 18);
    } catch (_) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo obtener tu ubicación')));
      }
    }
  }

  void _moverA(LatLng p, {double zoom = 18}) {
    _centro = p;
    _map?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: p, zoom: zoom)));
  }

  void _actualizarDireccion() {
    _debounceReverse?.cancel();
    _debounceReverse = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _cargandoDireccion = true);
      try {
        final d = await _geo.direccionDe(_centro);
        if (mounted) setState(() => _direccionPin = d);
      } catch (_) {
        if (mounted) setState(() => _direccionPin = null);
      } finally {
        if (mounted) setState(() => _cargandoDireccion = false);
      }
    });
  }

  void _buscar(String q) {
    _debounceBusqueda?.cancel();
    if (q.trim().length < 3) {
      setState(() => _sugerencias = const []);
      return;
    }
    _debounceBusqueda = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await _geo.autocompletar(q, _tokenSesion, cerca: _centro);
        if (mounted) setState(() => _sugerencias = r);
      } catch (_) {
        if (mounted) setState(() => _sugerencias = const []);
      }
    });
  }

  Future<void> _elegir(SugerenciaDireccion s) async {
    FocusScope.of(context).unfocus();
    setState(() => _sugerencias = const []);
    try {
      final lugar = await _geo.lugar(s.placeId, _tokenSesion);
      _tokenSesion = GeoService.nuevoTokenSesion(); // la sesión de Places termina al elegir
      _placeId = lugar.placeId;
      _busqueda.text = lugar.direccion;
      _moverA(lugar.posicion);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir esa dirección')));
      }
    }
  }

  Future<void> _confirmar() async {
    setState(() => _guardando = true);
    try {
      await _orders.saveOrderGeocode(
        widget.orderId,
        latitud: _centro.latitude,
        longitud: _centro.longitude,
        precision: 'manual',
        direccion: _direccionPin,
        placeId: _placeId,
      );
      GeoService.registrarPinCorregido(widget.orderId, _centro);
      if (!mounted) return;
      Navigator.pop(context, _centro);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ubicación de entrega guardada')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ubicación de entrega · ${widget.folio}')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _centro, zoom: widget.inicial != null ? 18 : 12),
            mapId: ApiConfig.mapsMapId.isEmpty ? null : ApiConfig.mapsMapId,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) => _map = c,
            onCameraMoveStarted: () => setState(() => _moviendo = true),
            onCameraMove: (p) => _centro = p.target,
            onCameraIdle: () {
              setState(() => _moviendo = false);
              _placeId = null; // el pin ya no es exactamente el lugar buscado
              _actualizarDireccion();
            },
          ),
          // Pin fijo al centro; se levanta mientras el mapa se mueve
          IgnorePointer(
            child: Center(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(bottom: _moviendo ? 58 : 44),
                child: const Icon(Icons.location_pin, size: 48, color: Color(0xFFD93025)),
              ),
            ),
          ),
          // Buscador de direcciones
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _busqueda,
                    onChanged: _buscar,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar dirección',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _busqueda.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _busqueda.clear();
                                setState(() => _sugerencias = const []);
                              },
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  if (_sugerencias.isNotEmpty) const Divider(height: 1),
                  ..._sugerencias.take(5).map((s) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(s.principal, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [s.secundario, if (s.metros != null) '${(s.metros! / 1000).toStringAsFixed(1)} km'].where((x) => x.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _elegir(s),
                      )),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 200,
            child: FloatingActionButton.small(
              heroTag: 'pin_mi_ubicacion',
              backgroundColor: Colors.white,
              onPressed: _usarMiUbicacion,
              child: const Icon(Icons.my_location, color: Color(0xFF1A73E8)),
            ),
          ),
          // Panel inferior: dirección del pin y confirmar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dirección de la orden', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    Text(widget.direccion, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Text('Donde quedó el pin', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    Text(
                      _cargandoDireccion ? 'Buscando…' : (_direccionPin ?? 'Mueve el mapa hasta la puerta de entrega'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: _guardando
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check),
                        label: const Text('Confirmar ubicación'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: _guardando || _moviendo ? null : _confirmar,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
