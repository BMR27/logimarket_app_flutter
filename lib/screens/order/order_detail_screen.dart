import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../providers/orders_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/map_navigation_provider.dart';
import '../../config/api_config.dart';
import '../../models/catalogs_model.dart';
import '../../services/catalogs_service.dart';
import '../../services/api_service.dart';
import 'delivery_evidence_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _catalogsService = CatalogsService();

  List<MotivoStatusModel> _motivos = [];
  List<MotivoExplicacionModel> _explicaciones = [];

  int? _selectedStatus;
  int? _selectedMotivo;
  int? _selectedExplicacion;
  DateTime? _fechaReagenda;
  bool _saving = false;

  // ── Notas del mensajero ───────────────────────────────────────────────────
  final _notesCtrl = TextEditingController();
  bool _savingNotes = false;
  bool _notesSaved = false;

  // ── Solicitud cambio de precio ────────────────────────────────────────────
  Map<String, dynamic>? _priceRequest;
  bool _loadingPriceRequest = false;

  // ── Evidencia de entrega ──────────────────────────────────────────────────
  Map<String, dynamic>? _evidencia;
  bool _loadingEvidencia = false;

  // Opciones de status de orden
  static const _statusOptions = [
    {'id': 1, 'name': 'Exitosa'},
    {'id': 2, 'name': 'Asignada'},
    {'id': 3, 'name': 'Sin Asignar'},
    {'id': 4, 'name': 'Cancelada'},
    {'id': 5, 'name': 'Intento 1'},
    {'id': 6, 'name': 'Intento 2'},
    {'id': 7, 'name': 'On Delivery'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    await context.read<OrdersProvider>().selectOrder(widget.orderId, auth.equiposForQuery);
    try {
      _motivos = await _catalogsService.getMotivosStatus();
      _explicaciones = await _catalogsService.getExplicacionesMotivo();
    } catch (_) {}
    await _loadPriceRequest();
      await _loadEvidencia();
    if (mounted) {
      final order = context.read<OrdersProvider>().selectedOrder;
      if (order != null) {
        _notesCtrl.text = order.observacionesMensajero ?? '';
        // Inicializar status solo si el valor está en las opciones válidas
        final validIds = _statusOptions.map((s) => s['id'] as int).toSet();
        _selectedStatus = validIds.contains(order.idStatus) ? order.idStatus : null;
      }
      setState(() {});
    }
  }

  Future<void> _loadPriceRequest() async {
    if (!mounted) return;
    setState(() => _loadingPriceRequest = true);
    try {
      final svc = ApiService();
      final data = await svc.get(ApiConfig.orderPriceRequest(widget.orderId));
      if (mounted) setState(() => _priceRequest = data != null ? Map<String, dynamic>.from(data as Map) : null);
    } catch (_) {
      if (mounted) setState(() => _priceRequest = null);
    }
    if (mounted) setState(() => _loadingPriceRequest = false);

    Future<void> _loadEvidencia() async {
      if (!mounted) return;
      setState(() => _loadingEvidencia = true);
      try {
        final svc = ApiService();
        final data = await svc.get(ApiConfig.orderEvidencia(widget.orderId));
        if (mounted) setState(() => _evidencia = data != null ? Map<String, dynamic>.from(data as Map) : null);
      } catch (_) {
        if (mounted) setState(() => _evidencia = null);
      }
      if (mounted) setState(() => _loadingEvidencia = false);
    }
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return 0;
  }

  Future<void> _saveNotes() async {
    final notes = _notesCtrl.text.trim();
    setState(() { _savingNotes = true; _notesSaved = false; });
    try {
      final svc = ApiService();
      await svc.put(ApiConfig.orderNotes(widget.orderId), {'observacionesMensajero': notes});
      if (mounted) setState(() => _notesSaved = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar notas: $e')));
      }
    }
    if (mounted) setState(() => _savingNotes = false);
  }

  Future<void> _showPriceRequestDialog() async {
    final auth = context.read<AuthProvider>();
    final priceCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Solicitar cambio de precio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio solicitado (MXN)',
                prefixText: '\$',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(labelText: 'Motivo del cambio'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enviar')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final precio = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
    if (precio == null || precio <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un precio válido')));
      return;
    }

    try {
      final svc = ApiService();
      await svc.post(ApiConfig.orderPriceRequest(widget.orderId), {
        'precioSolicitado': precio,
        'motivoSolicitud': motivoCtrl.text.trim(),
        'idUsuarioSolicita': auth.user!.idUsuario,
      });
      await _loadPriceRequest();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud enviada al supervisor'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    if (_selectedStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un status')),
      );
      return;
    }
    setState(() => _saving = true);
    final ok = await context.read<OrdersProvider>().updateOrder(
          idOrden: widget.orderId,
          status: _selectedStatus!,
          idUsuario: auth.user!.idUsuario,
          motivoStatus: _selectedMotivo ?? 0,
          explicacionMotivo: _selectedExplicacion ?? 0,
          fechaReagenda: _fechaReagenda?.toIso8601String(),
        );
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Pedido actualizado' : 'Guardado offline'),
        backgroundColor: ok ? Colors.green : Colors.orange,
      ));
      if (ok) Navigator.pop(context);
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/52$clean');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  /// Muestra un bottom sheet con opciones de navegación
  Future<void> _showNavigationOptions(String? lat, String? lng, String address) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Abrir con...',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1A73E8),
                  child: Icon(Icons.navigation, color: Colors.white, size: 20),
                ),
                title: const Text('Navegar en la app'),
                subtitle: const Text('Ruta en el mapa de Logimarket'),
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateInApp(lat, lng, address);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF4285F4),
                  child: Icon(Icons.map, color: Colors.white, size: 20),
                ),
                title: const Text('Google Maps'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openGoogleMaps(lat, lng, address);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF33CCFF),
                  child: Icon(Icons.directions_car, color: Colors.white, size: 20),
                ),
                title: const Text('Waze'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openWaze(lat, lng, address);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openGoogleMaps(String? lat, String? lng, String address) async {
    Uri uri;
    if (lat != null && lng != null &&
        double.tryParse(lat) != null && double.tryParse(lng) != null) {
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    } else {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    }
    if (await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openWaze(String? lat, String? lng, String address) async {
    Uri uri;
    if (lat != null && lng != null &&
        double.tryParse(lat) != null && double.tryParse(lng) != null) {
      uri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
    } else {
      uri = Uri.parse('waze://?q=${Uri.encodeComponent(address)}&navigate=yes');
    }
    if (!await canLaunchUrl(uri)) {
      // Fallback a waze web si no está instalado
      uri = Uri.parse('https://waze.com/ul?q=${Uri.encodeComponent(address)}&navigate=yes');
    }
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _navigateInApp(String? lat, String? lng, String address) async {
    double? destLat = double.tryParse(lat ?? '');
    double? destLng = double.tryParse(lng ?? '');

    // Si no hay coordenadas, geocodificar con Nominatim (OSM, sin API key)
    if (destLat == null || destLng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Buscando dirección en el mapa...')),
        );
      }

      final order = context.read<OrdersProvider>().selectedOrder!;
      final calleClean = _cleanStreet(order.calle);
      final cp = order.codigoPostal.trim();
      final colonia = order.colonia.trim();
      final municipio = order.municipioDelegacion.trim();
      final estado = order.estado.trim();
      final numExt = order.numExterior.trim();

      // Estrategia progresiva: de más específico a más general
      // El CP de México es muy preciso (5 dígitos), priorizar siempre
      final queries = [
        // 1. CP + calle limpia + número (más preciso para México)
        if (cp.isNotEmpty && calleClean.isNotEmpty && numExt.isNotEmpty)
          '$calleClean $numExt, $cp, Mexico',
        // 2. CP + calle + colonia
        if (cp.isNotEmpty && calleClean.isNotEmpty)
          '$calleClean, $cp $colonia, Mexico',
        // 3. Calle completa + colonia + municipio + CP
        if (calleClean.isNotEmpty)
          '$calleClean $numExt, $colonia, $municipio, $estado, Mexico',
        // 4. Solo CP + municipio (muy confiable en México)
        if (cp.isNotEmpty && municipio.isNotEmpty)
          '$cp $municipio, $estado, Mexico',
        // 5. Colonia + municipio + estado
        if (colonia.isNotEmpty)
          '$colonia, $municipio, $estado, Mexico',
        // 6. Solo municipio + estado (fallback final)
        '$municipio, $estado, Mexico',
      ];

      for (final q in queries) {
        try {
          final uri = Uri.parse(
            'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(q)}'
            '&format=json&limit=1&countrycodes=mx',
          );
          final response = await http.get(
            uri,
            headers: {'User-Agent': 'logimarket-app/1.0'},
          );
          if (response.statusCode == 200) {
            final results = jsonDecode(response.body) as List;
            if (results.isNotEmpty) {
              destLat = double.tryParse(results[0]['lat'] as String);
              destLng = double.tryParse(results[0]['lon'] as String);
              if (destLat != null && destLng != null) break;
            }
          }
        } catch (_) {}
      }

      if (destLat == null || destLng == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo encontrar la dirección en el mapa')),
          );
        }
        return;
      }
    }

    // Forzar posición GPS fresca (nunca usar posición en caché)
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo obtener tu ubicación actual')),
        );
      }
      return;
    }

    context.read<MapNavigationProvider>().setDestination(
          LatLng(destLat, destLng),
          LatLng(pos.latitude, pos.longitude),
          address: address,
        );

    // Regresar hasta la pantalla principal para que el listener cambie el tab al mapa
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Elimina prefijos de tipo de calle (Calle., Cerrada., Cda., Av., etc.)
  String _cleanStreet(String calle) {
    return calle
        .replaceAll(RegExp(r'^(Calle\.|Cerrada\.|Cda\.|Av\.|Blvd\.|Blvd |Calz\.|Col\.|Priv\.|Prol\.)\s*', caseSensitive: false), '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final ordersProvider = context.watch<OrdersProvider>();
    final order = ordersProvider.selectedOrder;

    if (ordersProvider.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle de orden')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  ordersProvider.errorMessage ?? 'No se pudo cargar la orden',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                  onPressed: _loadData,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final motivosFiltrados = _motivos
        .where((m) => m.idStatus == _selectedStatus)
        .toList();
    final explicacionesFiltradas = _explicaciones
        .where((e) => e.idMotivo == _selectedMotivo)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(order.folioOrdenCliente),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cliente ─────────────────────────────────────────────
            _Section(title: 'Cliente', children: [
              _InfoRow(icon: Icons.person, label: order.cliente),
              _InfoRow(
                icon: Icons.location_on,
                label: order.fullAddress,
                onTap: () => _showNavigationOptions(order.latitud, order.longitud, order.fullAddress),
              ),
              Row(
                children: [
                  Expanded(
                    child: _InfoRow(
                      icon: Icons.phone,
                      label: order.telefonoPrincipal,
                      onTap: () => _callPhone(order.telefonoPrincipal),
                    ),
                  ),
                  if (order.telefonoPrincipal.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.chat, color: Colors.green),
                      onPressed: () => _openWhatsApp(order.telefonoPrincipal),
                      tooltip: 'WhatsApp',
                    ),
                ],
              ),
              if (order.notas.isNotEmpty)
                _InfoRow(icon: Icons.notes, label: order.notas),
            ]),

            // ── Distancia / Tiempo ───────────────────────────────────
            if (order.metros != null || order.tiempo != null)
              _Section(title: 'Ruta', children: [
                Row(children: [
                  if (order.metros != null)
                    _Chip(icon: Icons.straighten, label: '${order.metros} m'),
                  const SizedBox(width: 8),
                  if (order.tiempo != null)
                    _Chip(icon: Icons.timer, label: '${order.tiempo} min'),
                ]),
              ]),

            // ── Productos ────────────────────────────────────────────
            _Section(
              title: 'Productos (${ordersProvider.products.length})',
              children: ordersProvider.products
                  .map((p) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.inventory_2_outlined, size: 18),
                        title: Text(p.descripcion, style: const TextStyle(fontSize: 13)),
                        trailing: Text('x${p.cantidad}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ))
                  .toList(),
            ),

            // ── Resumen financiero ────────────────────────────────────
            _Section(title: 'Resumen financiero', children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.attach_money, color: Colors.green),
                title: const Text('Total de la orden'),
                trailing: Text(
                  '\$${order.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (_loadingPriceRequest)
                const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
              if (_priceRequest != null) ...[
                const Divider(),
                ListTile(
                  dense: true,
                  leading: Icon(
                    _priceRequest!['estadoSolicitud'] == 'autorizada'
                        ? Icons.check_circle
                        : Icons.hourglass_top,
                    color: _priceRequest!['estadoSolicitud'] == 'autorizada'
                        ? Colors.green
                        : Colors.orange,
                  ),
                  title: Text('Cambio de precio: ${_priceRequest!['estadoSolicitud']}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Precio solicitado: \$${_asDouble(_priceRequest!['precioSolicitado']).toStringAsFixed(2)}'),
                      if ((_priceRequest!['motivoSolicitud'] ?? '').toString().isNotEmpty)
                        Text('Motivo: ${_priceRequest!['motivoSolicitud']}'),
                      if (_priceRequest!['totalAutorizado'] != null)
                        Text(
                          'Precio autorizado: \$${_asDouble(_priceRequest!['totalAutorizado']).toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
              ],
              if (_priceRequest == null || _priceRequest!['estadoSolicitud'] == 'cancelada') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.price_change_outlined),
                  label: const Text('Solicitar cambio de precio'),
                  onPressed: _showPriceRequestDialog,
                ),
              ],
            ]),

            // ── Notas del mensajero ───────────────────────────────────
            _Section(title: 'Notas / comentarios', children: [
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Agrega observaciones sobre esta orden...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (_notesSaved)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Notas guardadas ✓',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
              ElevatedButton.icon(
                icon: _savingNotes
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save, size: 18),
                label: const Text('Guardar notas'),
                onPressed: _savingNotes ? null : _saveNotes,
              ),
            ]),

            // ── Calificación ─────────────────────────────────────────
            _Section(title: 'Calificar entrega', children: [
                          // ── Evidencia de entrega ──────────────────────────────────
                          _Section(title: 'Evidencia de entrega', children: [
                            if (_loadingEvidencia)
                              const Padding(
                                padding: EdgeInsets.all(8),
                                child: LinearProgressIndicator(),
                              )
                            else if (_evidencia != null) ...[
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(
                                  backgroundColor: Colors.green,
                                  child: Icon(Icons.check, color: Colors.white, size: 20),
                                ),
                                title: Text(
                                  _evidencia!['nombreReceptor'] ?? 'Evidencia guardada',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: const Text('Foto y/o firma registradas'),
                              ),
                              const SizedBox(height: 8),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: Text(
                                  _evidencia == null
                                      ? 'Registrar foto y firma'
                                      : 'Ver / actualizar evidencia',
                                ),
                                onPressed: () async {
                                  final auth = context.read<AuthProvider>();
                                  final order = context.read<OrdersProvider>().selectedOrder;
                                  if (order == null || auth.user == null) return;
                                  final updated = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DeliveryEvidenceScreen(
                                        orderId: widget.orderId,
                                        idUsuario: auth.user!.idUsuario,
                                        folioOrden: order.folioOrdenCliente,
                                      ),
                                    ),
                                  );
                                  if (updated == true) _loadEvidencia();
                                },
                              ),
                            ),
                          ]),

                          // ── Calificación ─────────────────────────────────────────
                          _Section(title: 'Calificar entrega', children: [
              // Status
              DropdownButtonFormField<int>(
                value: _selectedStatus,
                decoration: const InputDecoration(labelText: 'Status'),
                items: _statusOptions
                    .map((s) => DropdownMenuItem(
                          value: s['id'] as int,
                          child: Text(s['name'] as String),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedStatus = v;
                  _selectedMotivo = null;
                  _selectedExplicacion = null;
                }),
              ),
              const SizedBox(height: 12),

              // Motivo (condicional)
              if (motivosFiltrados.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  value: _selectedMotivo,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                  items: motivosFiltrados
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.motivo),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedMotivo = v;
                    _selectedExplicacion = null;
                  }),
                ),
                const SizedBox(height: 12),
              ],

              // Explicación (condicional)
              if (explicacionesFiltradas.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  value: _selectedExplicacion,
                  decoration: const InputDecoration(labelText: 'Explicación'),
                  items: explicacionesFiltradas
                      .map((e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.explicacion),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedExplicacion = v),
                ),
                const SizedBox(height: 12),
              ],

              // Fecha reagenda
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(_fechaReagenda == null
                    ? 'Fecha de reagenda (opcional)'
                    : 'Reagenda: ${_fechaReagenda!.day}/${_fechaReagenda!.month}/${_fechaReagenda!.year}'),
                trailing: _fechaReagenda != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _fechaReagenda = null),
                      )
                    : null,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _fechaReagenda = picked);
                },
              ),

              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar calificación'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ──────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _InfoRow({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLink = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isLink ? Colors.blue : Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isLink ? Colors.blue : null,
                  decoration: isLink ? TextDecoration.underline : null,
                ),
              ),
            ),
            if (isLink)
              const Icon(Icons.directions, size: 18, color: Colors.blue),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blue),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.blue)),
        ],
      ),
    );
  }
}
