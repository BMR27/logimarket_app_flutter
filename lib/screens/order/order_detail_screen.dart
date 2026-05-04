import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/orders_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/map_navigation_provider.dart';
import '../../providers/backpacks_provider.dart';
import '../../config/api_config.dart';
import '../../models/catalogs_model.dart';
import '../../models/order_model.dart';
import '../../services/catalogs_service.dart';
import '../../services/api_service.dart';
import '../../services/orders_service.dart';
import '../../services/location_tracking_service.dart';
import 'delivery_evidence_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _catalogsService = CatalogsService();
  final _ordersService = OrdersService();

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

  // ── Historial de calificaciones ───────────────────────────────────────────
  List<Map<String, dynamic>> _statusHistory = [];
  bool _loadingStatusHistory = false;

  // ── Tracking GPS (Iniciar Viaje) ──────────────────────────────────────────
  bool _enViaje = false;

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

  String _statusNameById(int id) {
    final found = _statusOptions.where((s) => s['id'] == id).toList();
    if (found.isNotEmpty) return (found.first['name'] as String).trim();
    return 'Status $id';
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    await context.read<OrdersProvider>().selectOrder(widget.orderId, auth.equiposForQuery);

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

    try {
      final futures = <Future<void>>[
        _loadPriceRequest(),
        _loadEvidencia(),
        _loadStatusHistory(),
      ];

      if (_motivos.isEmpty) {
        futures.add(() async {
          _motivos = await _catalogsService.getMotivosStatus();
          _explicaciones = await _catalogsService.getExplicacionesMotivo();
        }());
      }

      await Future.wait(futures);
    } catch (_) {
      // Se mantiene la pantalla funcional aunque fallen cargas secundarias.
    }

    if (mounted) setState(() {});
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
  }

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

  Future<void> _loadStatusHistory() async {
    if (!mounted) return;
    setState(() => _loadingStatusHistory = true);
    try {
      final data = await _ordersService.getOrderStatusHistory(widget.orderId);
      if (mounted) setState(() => _statusHistory = data);
    } catch (_) {
      if (mounted) setState(() => _statusHistory = []);
    }
    if (mounted) setState(() => _loadingStatusHistory = false);
  }

  bool _hasIntento1Step(OrderModel? order) {
    if (order == null) return false;
    if (order.idStatus == 5 || order.idStatus == 6) return true;
    return _statusHistory.any((h) {
      final prev = _toInt(h['idStatusAnterior'] ?? h['statusAnterior']);
      final next = _toInt(h['idStatusNuevo'] ?? h['statusNuevo']);
      return prev == 5 || next == 5;
    });
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _historyDate(Map<String, dynamic> item) {
    final raw = item['creationDate'] ?? item['fechaModificacion'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  String _historyStatusLabel(dynamic statusTextOrId, dynamic idFallback) {
    final text = statusTextOrId?.toString().trim() ?? '';
    if (text.isNotEmpty && text != '-' && int.tryParse(text) == null) {
      return text;
    }
    final id = _toInt(idFallback);
    if (id > 0) return _statusNameById(id);
    final numericFromText = int.tryParse(text);
    if (numericFromText != null && numericFromText > 0) {
      return _statusNameById(numericFromText);
    }
    return '-';
  }

  List<Map<String, dynamic>> _historyAscending() {
    final sorted = List<Map<String, dynamic>>.from(_statusHistory);
    sorted.sort((a, b) {
      final da = _historyDate(a);
      final db = _historyDate(b);
      if (da == null && db == null) return 0;
      if (da == null) return -1;
      if (db == null) return 1;
      return da.compareTo(db);
    });
    return sorted;
  }

  List<String> _inferredPathFromCurrentStatus(int idStatus) {
    switch (idStatus) {
      case 1:
        return const ['Asignada', 'On Delivery', 'Exitosa'];
      case 4:
        return const ['Asignada', 'On Delivery', 'Cancelada'];
      case 5:
        return const ['Asignada', 'Intento 1'];
      case 6:
        return const ['Asignada', 'Intento 1', 'Intento 2'];
      case 7:
        return const ['Asignada', 'On Delivery'];
      case 2:
        return const ['Asignada'];
      case 3:
        return const ['Sin Asignar'];
      default:
        return [_statusNameById(idStatus)];
    }
  }

  List<String> _statusPath(OrderModel order) {
    if (_statusHistory.isEmpty) {
      return _inferredPathFromCurrentStatus(order.idStatus);
    }

    final path = <String>[];
    for (final h in _historyAscending()) {
      final anterior = (h['statusAnterior'] ?? '').toString().trim();
      final nuevo = (h['statusNuevo'] ?? '').toString().trim();

      if (anterior.isNotEmpty && anterior != '-' && (path.isEmpty || path.last != anterior)) {
        path.add(anterior);
      }
      if (nuevo.isNotEmpty && nuevo != '-' && (path.isEmpty || path.last != nuevo)) {
        path.add(nuevo);
      }
    }

    final current = order.statusOrden.trim();
    if (current.isNotEmpty && (path.isEmpty || path.last != current)) {
      path.add(current);
    }

    if (path.isEmpty) {
      return _inferredPathFromCurrentStatus(order.idStatus);
    }

    return path;
  }

  String _fmtHistoryDate(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return _fmtHistoryDate(raw['creationDate'] ?? raw['fechaModificacion']);
    }
    final text = raw?.toString() ?? '';
    if (text.isEmpty || text.length < 10) return '-';
    final y = text.substring(0, 4);
    final m = text.substring(5, 7);
    final d = text.substring(8, 10);
    final t = text.length >= 16 ? text.substring(11, 16) : '';
    return t.isNotEmpty ? '$d/$m/$y $t' : '$d/$m/$y';
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

  Future<void> _toggleViaje(AuthProvider auth) async {
    final tracker = LocationTrackingService.instance;
    if (_enViaje) {
      // Detener viaje
      await tracker.updateTrip(idOrden: widget.orderId, enViaje: false);
      setState(() => _enViaje = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viaje finalizado'), backgroundColor: Colors.orange),
      );
    } else {
      final hasAnotherActiveTrip =
          tracker.enViaje &&
          tracker.activeOrderId != null &&
          tracker.activeOrderId != widget.orderId;
      if (hasAnotherActiveTrip) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ya hay un viaje activo en la orden ${tracker.activeOrderId}. Finalizalo antes de iniciar otro.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Iniciar viaje — asegura que el tracker esté activo
      try {
        final token = await ApiService.getToken() ?? '';
        if (token.isEmpty || auth.user == null) {
          throw Exception('Sesión inválida. Vuelve a iniciar sesión.');
        }

        if (!tracker.isTracking) {
          await tracker.start(
            idMensajero: auth.user!.idUsuario,
            token: token,
            idOrden: widget.orderId,
            enViaje: true,
          );
        } else {
          await tracker.updateTrip(idOrden: widget.orderId, enViaje: true);
        }

        setState(() => _enViaje = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Viaje iniciado! Tu ubicación se está enviando'), backgroundColor: Colors.green),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar viaje: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Sincronizar estado de viaje con el tracker global
    _enViaje = LocationTrackingService.instance.isTracking &&
        LocationTrackingService.instance.enViaje &&
        LocationTrackingService.instance.activeOrderId == widget.orderId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MapNavigationProvider>().clearRoute();
      _loadData();
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    final order = context.read<OrdersProvider>().selectedOrder;
    if (_selectedStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un status')),
      );
      return;
    }
    if (_selectedStatus == 6 && !_hasIntento1Step(order)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes marcar Intento 2 sin haber pasado antes por Intento 1')),
      );
      return;
    }
    setState(() => _saving = true);
    bool ok = false;
    String? saveError;
    try {
      ok = await context.read<OrdersProvider>().updateOrder(
            idOrden: widget.orderId,
            status: _selectedStatus!,
            idUsuario: auth.user!.idUsuario,
            motivoStatus: _selectedMotivo ?? 0,
            explicacionMotivo: _selectedExplicacion ?? 0,
            fechaReagenda: _fechaReagenda?.toIso8601String(),
          );
    } on ApiException catch (e) {
      saveError = e.message;
    } catch (e) {
      saveError = 'No se pudo guardar la calificacion: $e';
    }
    setState(() => _saving = false);

    if (saveError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saveError), backgroundColor: Colors.red),
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Pedido actualizado' : 'Guardado offline'),
        backgroundColor: ok ? Colors.green : Colors.orange,
      ));
      if (ok) {
        await context.read<OrdersProvider>().loadOrders(auth.equiposForQuery);

        final backpacksProvider = context.read<BackpacksProvider>();
        final enRuta = backpacksProvider.backpacks.where((b) => b.state == 2).toList();
        final primaryBackpack = enRuta.isNotEmpty
            ? enRuta.first
            : (backpacksProvider.backpacks.isNotEmpty ? backpacksProvider.backpacks.first : null);
        final isAdmin = auth.user?.type.toLowerCase() == 'admin' ||
            auth.user?.type.toLowerCase() == 'lider';
        await backpacksProvider.loadMapItems(
          isAdmin: isAdmin,
          userId: auth.user!.idUsuario,
          idBackpack: primaryBackpack?.id,
          idRepartidor: primaryBackpack?.idRepartidor,
          idBackpackIds: enRuta.map((b) => b.id).toList(),
        );

        if (mounted) Navigator.pop(context);
      }
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
    if (!_enViaje) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero debes iniciar viaje para abrir navegacion'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
                  'Abrir navegacion con...',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const Divider(),
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

  @override
  Widget build(BuildContext context) {
    final ordersProvider = context.watch<OrdersProvider>();
    final order = ordersProvider.selectedOrder;

    if (ordersProvider.loading && order == null) {
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
    final hasIntento1 = _hasIntento1Step(order);
    final isLockedBySuccess = order.idStatus == 1;
    final historyItems = _historyAscending();
    final statusPath = _statusPath(order);

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
                onTap: _enViaje
                    ? () => _showNavigationOptions(
                          order.latitud,
                          order.longitud,
                          order.fullAddress,
                        )
                    : null,
              ),
              // ── Botón Iniciar / Finalizar Viaje ─────────────────
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: Builder(
                    builder: (ctx) {
                      final auth = ctx.read<AuthProvider>();
                      return FilledButton.icon(
                        icon: Icon(_enViaje ? Icons.stop_circle_outlined : Icons.play_circle_outlined),
                        label: Text(_enViaje ? 'Finalizar Viaje' : 'Iniciar Viaje'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _enViaje ? Colors.red.shade600 : Colors.green.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async => _toggleViaje(auth),
                      );
                    },
                  ),
                ),
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
                          enabled: (s['id'] as int) != 6 || hasIntento1,
                          child: Text(s['name'] as String),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == 6 && !hasIntento1) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Primero debes pasar por Intento 1 antes de seleccionar Intento 2')),
                    );
                    return;
                  }
                  setState(() {
                    _selectedStatus = v;
                    _selectedMotivo = null;
                    _selectedExplicacion = null;
                  });
                },
              ),
              if (!hasIntento1)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Intento 2 estará disponible cuando esta orden haya pasado por Intento 1.',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
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
                        onPressed: isLockedBySuccess
                            ? null
                            : () => setState(() => _fechaReagenda = null),
                      )
                    : null,
                onTap: isLockedBySuccess
                    ? null
                    : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _fechaReagenda = picked);
                },
              ),
              if (isLockedBySuccess)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Reagenda bloqueada: la orden ya fue guardada como Exitosa.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
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

            // ── Historial de calificaciones ─────────────────────────
            _Section(title: 'Historial de calificaciones', children: [
              if (_loadingStatusHistory)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                )
              else ...[
                if (statusPath.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: statusPath
                          .map((s) => Chip(label: Text(s), visualDensity: VisualDensity.compact))
                          .toList(),
                    ),
                  ),
                if (historyItems.isEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, size: 18),
                    title: Text(
                      'Estado actual: ${order.statusOrden.trim().isNotEmpty ? order.statusOrden : _statusNameById(order.idStatus)}',
                    ),
                    subtitle: const Text('No hay transiciones guardadas; mostrando flujo por status actual.'),
                  )
                else
                  ...historyItems.map((h) {
                  final anterior = _historyStatusLabel(
                    h['statusAnterior'],
                    h['idStatusAnterior'] ?? h['statusAnterior'],
                  );
                  final nuevo = _historyStatusLabel(
                    h['statusNuevo'],
                    h['idStatusNuevo'] ?? h['statusNuevo'],
                  );
                  final motivo = (h['motivoStatus'] ?? h['motivoCambio'] ?? '').toString();
                  final explicacion = (h['explicacionMotivo'] ?? '').toString();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, size: 18),
                    title: Text('$anterior → $nuevo'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fecha modificación: ${_fmtHistoryDate(h)}'),
                        if (motivo.isNotEmpty) Text('Motivo: $motivo'),
                        if (explicacion.isNotEmpty) Text('Explicación: $explicacion'),
                      ],
                    ),
                  );
                }),
              ],
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
