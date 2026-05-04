import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/orders_provider.dart';
import '../../providers/map_navigation_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backpacks_provider.dart';
import '../../models/order_model.dart';
import '../../models/backpack_item_model.dart';
import '../../services/orders_service.dart';
import '../../config/api_config.dart';
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final _ordersService = OrdersService();
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _followUser = true;
  Set<Marker> _markers = {};
  bool _routeAnimated = false;
  bool _locationCentered = false; // Para centrar solo la primera vez al arrancar
  bool _loadingDeliverItems = false;
  bool _pinsFramed = false;
  String? _loadedEnRutaBackpacksKey;
  bool _resolvingMissingCoords = false;
  final Map<int, LatLng> _derivedCoordsByOrderId = {};
  final Map<int, int> _coordLookupAttemptsByOrderId = {};
  final Map<int, DateTime> _coordLastAttemptAtByOrderId = {};
  final Set<int> _detailLookupFailedOrderIds = <int>{};
  final Set<int> _addressLookupFailedOrderIds = <int>{};
  String? _lastAddressDumpKey;
  int _coordResolvedCount = 0;
  int _coordFailedCount = 0;

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
      _startLocationUpdates();
    }
  }

  Future<void> _centerOnUser() async {
    try {
      final pos = _currentPosition ??
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(const Duration(seconds: 10));
      if (!mounted || _mapController == null) return;
      if (mounted) setState(() => _currentPosition = pos);
      _locationCentered = true;
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: 15,
          ),
        ),
      );
    } catch (_) {
      // Si falla, el stream lo manejará
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

  double? _parseCoord(String? value) {
    if (value == null) return null;
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  // Valida que una coordenada esté dentro de los límites de México
  bool _isWithinMexico(double lat, double lng) {
    return lat >= 14.5 && lat <= 32.7 && lng >= -117.1 && lng <= -86.7;
  }

  bool _isOrderActiveInRoute(int statusId) {
    // Excluir status cerrados por ID numérico
    // 1=Exitosa, 4=Cancelada, 8,9,10=otros cerrados
    // 7=On Delivery es ACTIVO (repartidor en camino), NO se excluye
    const closedStatuses = {1, 4, 8, 9, 10};
    return !closedStatuses.contains(statusId);
  }

  bool _isBackpackItemActiveInRoute(
    BackpackItemModel item,
    Map<int, int> statusByOrderId,
  ) {
    if (item.isValidated) return false;

    // Priorizar status numérico para evitar falsos negativos por texto parcial
    if (!_isOrderActiveInRoute(item.idStatusOrden)) {
      return false;
    }

    // Fallback por texto para estados claramente cerrados (por si el ID no está mapeado)
    final statusText = item.statusName.toLowerCase();
    final closedByText = statusText.contains('exitosa') ||
        statusText.contains('cancelada') ||
        statusText.contains('devuelta');
    if (closedByText) return false;

    // Si existe un status de la orden, excluir solo los cerrados.
    final orderStatus = statusByOrderId[item.idOrdenVenta];
    if (orderStatus != null && !_isOrderActiveInRoute(orderStatus)) {
      return false;
    }

    // Si llegó a mochila En Ruta y no está cerrada/validada, debe verse.
    return true;
  }

  Future<LatLng?> _resolveCoordFromOrder(OrderModel order) async {
    try {
      final lat = _parseCoord(order.latitud);
      final lng = _parseCoord(order.longitud);
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
      final query = order.fullAddress.trim();
      if (query.isEmpty) return null;
      return await _geocodeAddress(query);
    } catch (_) {
      return null;
    }
  }

  void _debugDumpBackpackAddresses(
    List<BackpackItemModel> allItems,
    List<BackpackItemModel> activeItems,
    Map<int, int> statusByOrderId,
    List<OrderModel> allOrders,
    String enRutaKey,
  ) {
    final dumpKey = '$enRutaKey|all:${allItems.length}|act:${activeItems.length}';
    if (_lastAddressDumpKey == dumpKey) return;
    _lastAddressDumpKey = dumpKey;

    final activeIds = activeItems.map((i) => i.idBackpackItem).toSet();
    final orderById = <int, OrderModel>{for (final o in allOrders) o.id: o};

    debugPrint('[MAP][DEBUG] ------- DUMP DIRECCIONES MOCHILA -------');
    for (final item in allItems) {
      final order = orderById[item.idOrdenVenta];
      final orderStatus = statusByOrderId[item.idOrdenVenta];
      final isActive = activeIds.contains(item.idBackpackItem);
      final reason = isActive
          ? 'ACTIVA'
          : (item.isValidated
                ? 'EXCLUIDA:VALIDADA'
                : (!_isOrderActiveInRoute(item.idStatusOrden)
                    ? 'EXCLUIDA:STATUS_ITEM_CERRADO(${item.idStatusOrden})'
                    : (orderStatus != null && !_isOrderActiveInRoute(orderStatus)
                        ? 'EXCLUIDA:STATUS_ORDEN_CERRADO($orderStatus)'
                        : 'EXCLUIDA:STATUS_TEXTO(${item.statusName})')));

      debugPrint(
        '[MAP][DEBUG] OV:${item.idOrdenVenta} Folio:${item.folioOrden} Bp:${item.idBackpack} '
        'StatItem:${item.idStatusOrden}/${item.statusName} StatOrden:${orderStatus ?? -1} '
        'Reason:$reason | ItemAddr:"${item.fullAddress}" | OrderAddr:"${order?.fullAddress ?? ''}"',
      );
    }
    debugPrint('[MAP][DEBUG] --------------------------------------');
  }

  Future<void> _resolveMissingCoords(
    List<BackpackItemModel> items,
    Map<int, LatLng> coordsByOrderId,
    List<OrderModel> allOrders,
    String equipos,
  ) async {
    if (_resolvingMissingCoords) return;

    final orderById = <int, OrderModel>{
      for (final o in allOrders) o.id: o,
    };

    List<BackpackItemModel> buildMissingBatch() {
      final now = DateTime.now();
      return items.where((i) {
        final orderId = i.idOrdenVenta;
        if (coordsByOrderId.containsKey(orderId) ||
            _derivedCoordsByOrderId.containsKey(orderId)) {
          return false;
        }

        final attempts = _coordLookupAttemptsByOrderId[orderId] ?? 0;
        if (attempts >= 3) return false;

        final lastAttemptAt = _coordLastAttemptAtByOrderId[orderId];
        if (lastAttemptAt != null &&
            now.difference(lastAttemptAt) < const Duration(seconds: 2)) {
          return false;
        }

        return true;
      }).take(8).toList();
    }

    if (buildMissingBatch().isEmpty) return;

    _resolvingMissingCoords = true;

    try {
      while (true) {
        final missingItems = buildMissingBatch();
        if (missingItems.isEmpty) break;

        for (final item in missingItems) {
          final orderId = item.idOrdenVenta;
          _coordLookupAttemptsByOrderId[orderId] =
              (_coordLookupAttemptsByOrderId[orderId] ?? 0) + 1;
          _coordLastAttemptAtByOrderId[orderId] = DateTime.now();
          LatLng? resolved;

          final order = orderById[orderId];
          final candidates = _buildAddressCandidates(item, order);

          for (final address in candidates) {
            resolved = await _geocodeAddress(address);
            if (resolved != null) break;
          }

          if (resolved == null && order != null) {
            resolved = await _resolveCoordFromOrder(order);
          }

          if (resolved == null && orderId > 0) {
            // Intenta obtener la orden completa con el detail endpoint
            // Usar una sola variante de equipos para evitar ruido por 404 duplicado.
            final eq = equipos.trim();
            if (!_detailLookupFailedOrderIds.contains(orderId)) {
              try {
                final detail =
                    await _ordersService.getOrderDetail(orderId, equipos: eq);
                debugPrint('[MAP][DETAIL] OV:$orderId eq:"$eq" addr:"${detail.fullAddress}" lat:${detail.latitud}');
                final detailCandidates = _buildAddressCandidates(item, detail);
                for (final address in detailCandidates) {
                  resolved = await _geocodeAddress(address);
                  if (resolved != null) break;
                }
                resolved ??= await _resolveCoordFromOrder(detail);
              } catch (e) {
                debugPrint('[MAP][DETAIL] OV:$orderId eq:"$eq" ERROR: $e');
                _detailLookupFailedOrderIds.add(orderId);
              }
            }

            // Último fallback: endpoint directo de dirección sin filtro de equipo
            if (resolved == null && !_addressLookupFailedOrderIds.contains(orderId)) {
              try {
                final addr = await _ordersService.getOrderAddress(orderId);
                debugPrint('[MAP][ADDR] OV:$orderId addr:"${addr.fullAddress}" lat:${addr.latitud}');
                final addrCandidates = _buildAddressCandidates(item, addr);
                for (final address in addrCandidates) {
                  resolved = await _geocodeAddress(address);
                  if (resolved != null) break;
                }
                resolved ??= await _resolveCoordFromOrder(addr);
              } catch (e) {
                debugPrint('[MAP][ADDR] OV:$orderId ERROR: $e');
                _addressLookupFailedOrderIds.add(orderId);
              }
            }
          }

          if (resolved != null) {
            _derivedCoordsByOrderId[orderId] = resolved;
            _coordResolvedCount++;
          } else {
            _coordFailedCount++;
          }
        }

        if (mounted) setState(() {});
        await Future.delayed(const Duration(milliseconds: 450));
      }
    } finally {
      _resolvingMissingCoords = false;
      if (mounted) setState(() {});
    }
  }

  List<String> _buildAddressCandidates(BackpackItemModel item, OrderModel? order) {
    final candidates = <String>[];
    // Contexto de estado para anclar la búsqueda en la zona correcta
    final estado = (item.estado ?? order?.estado ?? '').trim();
    final municipio = (item.municipio ?? order?.municipioDelegacion ?? '').trim();
    final suffix = estado.isNotEmpty ? ', $estado, Mexico' : ', Mexico';

    void add(String? raw) {
      final value = (raw ?? '').trim();
      if (value.isEmpty) return;
      // Siempre agregar versión con sufijo de estado para anclar geocoding
      final withState = estado.isNotEmpty ? '$value$suffix' : value;
      if (!candidates.contains(withState)) candidates.add(withState);
      if (!candidates.contains(value)) candidates.add(value);
    }

    // Candidato más específico primero: calle + municipio + estado
    final calle = '${item.calle ?? ''} ${item.numExterior ?? ''}'.trim();
    final colonia = item.colonia ?? '';
    final cp = (item.codigoPostal ?? order?.codigoPostal ?? '').trim();

    // CP es el ancla más confiable para geocodificar en México
    if (cp.isNotEmpty && calle.isNotEmpty) {
      candidates.add('$calle, $colonia, $cp, Mexico');
    }
    if (cp.isNotEmpty && colonia.isNotEmpty) {
      candidates.add('$colonia, $cp, Mexico');
    }
    if (cp.isNotEmpty && municipio.isNotEmpty) {
      candidates.add('$cp, $municipio, Mexico');
    }
    if (cp.isNotEmpty) {
      candidates.add('$cp, Mexico');
    }

    if (calle.isNotEmpty && municipio.isNotEmpty) {
      add('$calle, $colonia, $municipio$suffix');
    }
    if (colonia.isNotEmpty && municipio.isNotEmpty) {
      add('$colonia, $municipio$suffix');
    }
    add(item.fullAddress);

    if (order != null) {
      final oCalle = '${order.calle} ${order.numExterior}'.trim();
      final oMunicipio = order.municipioDelegacion.trim();
      final oEstado = order.estado.trim();
      final oCP = order.codigoPostal.trim();
      if (oCP.isNotEmpty && oCalle.isNotEmpty) {
        candidates.add('$oCalle, ${order.colonia}, CP $oCP, Mexico');
      }
      if (oCP.isNotEmpty && order.colonia.isNotEmpty) {
        candidates.add('${order.colonia}, CP $oCP, Mexico');
      }
      if (oCalle.isNotEmpty && oMunicipio.isNotEmpty) {
        add('$oCalle, ${order.colonia}, $oMunicipio, $oEstado, Mexico');
      }
      add('${order.colonia}, $oMunicipio, $oEstado, Mexico');
      add(order.fullAddress);
    }

    return candidates;
  }

  Future<LatLng?> _geocodeAddress(String query) async {
    try {
      // 1) Geocodificador nativo del dispositivo (Google/Apple según plataforma)
      try {
        final locations = await geo.locationFromAddress(query);
        if (locations.isNotEmpty) {
          final loc = locations.first;
          if (_isWithinMexico(loc.latitude, loc.longitude)) {
            return LatLng(loc.latitude, loc.longitude);
          }
        }
      } catch (_) {
        // Fallback a proveedores HTTP
      }

      // 2) Google Geocoding API (si hay key disponible)
      final googleKey = ApiConfig.mapsApiKey.trim();
      if (googleKey.isNotEmpty) {
        final googleUri = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?address=${Uri.encodeComponent(query)}&region=mx&language=es&key=${Uri.encodeComponent(googleKey)}',
        );

        final googleResp = await http.get(googleUri);
        if (googleResp.statusCode == 200) {
          final googleData = jsonDecode(googleResp.body) as Map<String, dynamic>;
          final status = (googleData['status'] ?? '').toString();
          if (status == 'OK') {
            final results = (googleData['results'] as List?) ?? const [];
            if (results.isNotEmpty) {
              final location = (results.first['geometry']?['location']) as Map<String, dynamic>?;
              final lat = (location?['lat'] as num?)?.toDouble();
              final lng = (location?['lng'] as num?)?.toDouble();
              if (lat != null && lng != null && _isWithinMexico(lat, lng)) return LatLng(lat, lng);
            }
          }
        }
      }

      // 3) Nominatim como último respaldo
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}&format=json&limit=1&countrycodes=mx',
      );
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'logimarket-app/1.0'},
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as List;
      if (data.isEmpty) return null;
      final geoLat = double.tryParse((data.first['lat'] ?? '').toString());
      final geoLng = double.tryParse((data.first['lon'] ?? '').toString());
      if (geoLat == null || geoLng == null) return null;
      if (!_isWithinMexico(geoLat, geoLng)) return null;
      return LatLng(geoLat, geoLng);
    } catch (_) {
      return null;
    }
  }

  void _buildMarkers(List<OrderModel> orders, LatLng? destination) {
    _markers = orders
        .where((o) => o.latitud != null && o.longitud != null)
        .map((o) {
      final lat = _parseCoord(o.latitud);
      final lng = _parseCoord(o.longitud);
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
        zIndexInt: 2,
      ));
    }
  }

  void _buildBackpackMarkers(
    List<BackpackItemModel> items,
    LatLng? destination,
    Map<int, LatLng> coordsByOrderId,
    Map<String, LatLng> coordsByFolio,
  ) {
    final pointsKeyToIndices = <String, List<int>>{};
    final orderedItems = items.where((i) => !i.isValidated).toList();
    final basePositions = <LatLng>[];

    for (var idx = 0; idx < orderedItems.length; idx++) {
      final i = orderedItems[idx];
      final lat = _parseCoord(i.latitud);
      final lng = _parseCoord(i.longitud);
      final directPos = (lat != null && lng != null && _isWithinMexico(lat, lng))
          ? LatLng(lat, lng)
          : null;
      final fallback =
          coordsByOrderId[i.idOrdenVenta] ?? coordsByFolio[i.folioOrden.trim()];
      final basePos = directPos ?? fallback;
      if (basePos == null) continue;
      basePositions.add(basePos);
      final key =
          '${basePos.latitude.toStringAsFixed(5)},${basePos.longitude.toStringAsFixed(5)}';
      pointsKeyToIndices.putIfAbsent(key, () => <int>[]).add(idx);
    }

    LatLng fallbackCenter;
    if (basePositions.isNotEmpty) {
      final latAvg =
          basePositions.map((p) => p.latitude).reduce((a, b) => a + b) /
              basePositions.length;
      final lngAvg =
          basePositions.map((p) => p.longitude).reduce((a, b) => a + b) /
              basePositions.length;
      fallbackCenter = LatLng(latAvg, lngAvg);
    } else if (_currentPosition != null) {
      fallbackCenter =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    } else {
      fallbackCenter = _initialCamera.target;
    }

    var missingIndex = 0;

    _markers = orderedItems.asMap().entries.map((entry) {
      final idx = entry.key;
      final i = entry.value;
      final lat = _parseCoord(i.latitud);
      final lng = _parseCoord(i.longitud);
      // Solo usar coordenadas directas si están dentro de México
      final directPos = (lat != null && lng != null && _isWithinMexico(lat, lng))
          ? LatLng(lat, lng)
          : null;
      final fallback =
          coordsByOrderId[i.idOrdenVenta] ?? coordsByFolio[i.folioOrden.trim()];
      final basePos = directPos ?? fallback;
      final isFallbackWithoutCoords = basePos == null;

      late final LatLng markerPos;
      if (isFallbackWithoutCoords) {
        final angle = (2 * pi * (missingIndex % 12)) / 12;
        final radius = 0.0012 + ((missingIndex ~/ 12) * 0.00045);
        markerPos = LatLng(
          fallbackCenter.latitude + radius * sin(angle),
          fallbackCenter.longitude + radius * cos(angle),
        );
        missingIndex++;
      } else {
        final key =
            '${basePos!.latitude.toStringAsFixed(5)},${basePos.longitude.toStringAsFixed(5)}';
        final overlapGroup = pointsKeyToIndices[key] ?? const <int>[];
        final groupSize = overlapGroup.length;
        final groupIndex = overlapGroup.indexOf(idx);
        markerPos = groupSize > 1
            ? _offsetOverlappingPin(basePos, groupIndex, groupSize)
            : basePos;
      }

      final detailSnippet = [
        i.nombreCliente.trim(),
        'Mochila ${i.idBackpack}',
        i.statusName.trim(),
        if (isFallbackWithoutCoords) 'Coordenada pendiente',
      ].where((v) => v.isNotEmpty).join(' | ');

      return Marker(
        markerId: MarkerId('bp_item_${i.idBackpackItem}'),
        position: markerPos,
        infoWindow: InfoWindow(
          title: '${i.folioOrden} (OV ${i.idOrdenVenta})',
          snippet: detailSnippet,
        ),
      );
    }).whereType<Marker>().toSet();

    if (destination != null) {
      _markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destino'),
        zIndexInt: 2,
      ));
    }
  }

  LatLng _offsetOverlappingPin(LatLng base, int groupIndex, int groupSize) {
    if (groupSize <= 1 || groupIndex < 0) return base;

    final ringRadius = 0.0006; // ~65m para separar pines traslapados visualmente
    final angle = (2 * pi * groupIndex) / groupSize;
    final latOffset = ringRadius * sin(angle);
    final lngOffset = ringRadius * cos(angle);
    return LatLng(base.latitude + latOffset, base.longitude + lngOffset);
  }

  void _animateToBounds(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
    // Solo incluir puntos dentro de México para evitar que 1 pin lejano aleje todo el mapa
    final mexicoPoints = points.where((p) => _isWithinMexico(p.latitude, p.longitude)).toList();
    final validPoints = mexicoPoints.isNotEmpty ? mexicoPoints : points;
    double minLat = validPoints.first.latitude, maxLat = validPoints.first.latitude;
    double minLng = validPoints.first.longitude, maxLng = validPoints.first.longitude;
    for (final p in validPoints) {
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

  Future<void> _openExternalNavigator({
    required bool waze,
    LatLng? destination,
    String? address,
  }) async {
    Uri uri;
    final hasCoords = destination != null;
    final query = (address ?? '').trim();

    if (waze) {
      if (hasCoords) {
        uri = Uri.parse(
          'waze://?ll=${destination!.latitude},${destination.longitude}&navigate=yes',
        );
      } else {
        uri = Uri.parse('waze://?q=${Uri.encodeComponent(query)}&navigate=yes');
      }

      if (!await canLaunchUrl(uri)) {
        if (hasCoords) {
          uri = Uri.parse(
            'https://waze.com/ul?ll=${destination!.latitude},${destination.longitude}&navigate=yes',
          );
        } else {
          uri = Uri.parse(
            'https://waze.com/ul?q=${Uri.encodeComponent(query)}&navigate=yes',
          );
        }
      }
    } else {
      if (hasCoords) {
        uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${destination!.latitude},${destination.longitude}&travelmode=driving',
        );
      } else {
        uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
        );
      }
    }

    if (!await canLaunchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el navegador externo')),
      );
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersProvider>().orders;
    final auth = context.watch<AuthProvider>();
    final backpacks = context.watch<BackpacksProvider>();
    final mapNav = context.watch<MapNavigationProvider>();
    final isNavigating = mapNav.destination != null;

    final isAdmin = auth.user?.type.toLowerCase() == 'admin' ||
        auth.user?.type.toLowerCase() == 'lider';
    final enRutaBackpacks = backpacks.backpacks.where((b) => b.state == 2).toList();
    final hasEnRutaBackpack = enRutaBackpacks.isNotEmpty;
    final enRutaBackpackIds = enRutaBackpacks.map((b) => b.id).toSet();
    final enRutaBackpacksKey = enRutaBackpackIds.toList()..sort();
    final enRutaKey = enRutaBackpacksKey.join(',');
    final primaryBackpack = hasEnRutaBackpack
      ? enRutaBackpacks.first
      : (backpacks.backpacks.isNotEmpty ? backpacks.backpacks.first : null);
    final targetBackpackId = primaryBackpack?.id;
    final pendingBackpackItems = hasEnRutaBackpack
      ? backpacks.selectedItems
        .where((i) => enRutaBackpackIds.contains(i.idBackpack))
        .toList()
      : <BackpackItemModel>[];
    final statusByOrderId = <int, int>{
      for (final o in orders) o.id: o.idStatus,
    };
    final coordsByOrderId = <int, LatLng>{};
    final coordsByFolio = <String, LatLng>{};
    for (final o in orders) {
      final lat = _parseCoord(o.latitud);
      final lng = _parseCoord(o.longitud);
      // Solo usar coordenadas de órdenes que estén dentro de México
      if (lat == null || lng == null || !_isWithinMexico(lat, lng)) continue;
      final pos = LatLng(lat, lng);
      coordsByOrderId[o.id] = pos;
      final folio = o.folioOrdenCliente.trim();
      if (folio.isNotEmpty) coordsByFolio[folio] = pos;
    }
    for (final entry in _derivedCoordsByOrderId.entries) {
      coordsByOrderId.putIfAbsent(entry.key, () => entry.value);
    }
    final activeBackpackItems = pendingBackpackItems
        .where((i) => _isBackpackItemActiveInRoute(i, statusByOrderId))
        .toList();
    final filteredOutCount = pendingBackpackItems.length - activeBackpackItems.length;

    if (!isAdmin && hasEnRutaBackpack && pendingBackpackItems.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _debugDumpBackpackAddresses(
          pendingBackpackItems,
          activeBackpackItems,
          statusByOrderId,
          orders,
          enRutaKey,
        );
      });
    }

    final pendingWithCoords = activeBackpackItems.where((i) {
      final lat = _parseCoord(i.latitud);
      final lng = _parseCoord(i.longitud);
      if (lat != null && lng != null) return true;
      return coordsByOrderId[i.idOrdenVenta] != null ||
          coordsByFolio[i.folioOrden.trim()] != null;
    }).toList();
    final missingCoordsCount = activeBackpackItems.length - pendingWithCoords.length;

    if (!isAdmin &&
        activeBackpackItems.isNotEmpty &&
        missingCoordsCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolveMissingCoords(
          activeBackpackItems,
          coordsByOrderId,
          orders,
          auth.equiposForQuery,
        );
      });
    }

    if (!isAdmin &&
        ((hasEnRutaBackpack &&
                (_loadedEnRutaBackpacksKey != enRutaKey || pendingBackpackItems.isEmpty)) ||
            backpacks.selectedItems.isEmpty) &&
        !_loadingDeliverItems) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _loadingDeliverItems) return;
        _loadingDeliverItems = true;
        final userId = auth.user?.idUsuario;
        final idRepartidor = primaryBackpack?.idRepartidor;
        if (userId != null) {
          await context.read<BackpacksProvider>().loadMapItems(
                isAdmin: isAdmin,
                userId: userId,
                idBackpack: targetBackpackId,
                idRepartidor: idRepartidor,
                idBackpackIds: enRutaBackpackIds.toList(),
              );
        }
        _loadedEnRutaBackpacksKey = enRutaKey;
        _loadingDeliverItems = false;
      });
    }

    if (!isAdmin && activeBackpackItems.isNotEmpty) {
      _buildBackpackMarkers(
        activeBackpackItems,
        mapNav.destination,
        coordsByOrderId,
        coordsByFolio,
      );
    } else {
      _buildMarkers(orders, mapNav.destination);
    }

    if (!isNavigating && !isAdmin && pendingWithCoords.isNotEmpty && !_pinsFramed) {
      _pinsFramed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final points = pendingWithCoords
          .map((i) {
            final lat = _parseCoord(i.latitud);
            final lng = _parseCoord(i.longitud);
            if (lat != null && lng != null) return LatLng(lat, lng);
            return coordsByOrderId[i.idOrdenVenta] ??
              coordsByFolio[i.folioOrden.trim()]!;
          })
            .toList();
        if (_currentPosition != null) {
          points.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
        }
        _animateToBounds(points);
      });
    }
    if (pendingWithCoords.isEmpty) {
      _pinsFramed = false;
    }

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
              if (mapNav.routePoints.isNotEmpty) {
                _animateToBounds(mapNav.routePoints);
              } else if (!_locationCentered) {
                _centerOnUser();
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

        if (!mapNav.loading && mapNav.routeError != null)
          Positioned(
            top: 60,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFD93025),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))
                ],
              ),
              child: Text(
                mapNav.routeError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

        // Diagnóstico temporal del mapa (puede retirarse cuando esté validado)
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Ruta:${hasEnRutaBackpack ? 'si' : 'no'} Bp:${enRutaBackpackIds.length} Pend:${pendingBackpackItems.length} Act:${activeBackpackItems.length} Fil:${filteredOutCount} Coord:${pendingWithCoords.length} Miss:${missingCoordsCount} Ok:${_coordResolvedCount} Err:${_coordFailedCount} Pins:${_markers.length}',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
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
              onOpenGoogleMaps: () => _openExternalNavigator(
                waze: false,
                destination: mapNav.destination,
                address: mapNav.destinationAddress,
              ),
              onOpenWaze: () => _openExternalNavigator(
                waze: true,
                destination: mapNav.destination,
                address: mapNav.destinationAddress,
              ),
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
  final VoidCallback onOpenGoogleMaps;
  final VoidCallback onOpenWaze;

  const _NavigationPanel({
    required this.mapNav,
    required this.onStart,
    required this.onStop,
    required this.onRecenter,
    required this.onOpenGoogleMaps,
    required this.onOpenWaze,
  });

  @override
  Widget build(BuildContext context) {
    final address = mapNav.destinationAddress ?? 'Destino';
    final hasRoute = mapNav.routePoints.length > 1;
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
                    onPressed: hasRoute ? onStart : null,
                    icon: const Icon(Icons.navigation, size: 20),
                    label: Text(
                      hasRoute ? 'Iniciar viaje' : 'Sin ruta disponible',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                if (!hasRoute) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onOpenGoogleMaps,
                          icon: const Icon(Icons.map, size: 18),
                          label: const Text('Google Maps'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onOpenWaze,
                          icon: const Icon(Icons.directions_car, size: 18),
                          label: const Text('Waze'),
                        ),
                      ),
                    ],
                  ),
                ],
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

