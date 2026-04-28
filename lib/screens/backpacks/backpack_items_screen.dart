import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/backpacks_provider.dart';
import '../../models/backpack_item_model.dart';
import '../order/order_detail_screen.dart';

class BackpackItemsScreen extends StatefulWidget {
  final int backpackId;
  final bool isAdmin;
  final int backpackState;
  const BackpackItemsScreen({
    super.key,
    required this.backpackId,
    required this.isAdmin,
    this.backpackState = 1,
  });

  @override
  State<BackpackItemsScreen> createState() => _BackpackItemsScreenState();
}

class _BackpackItemsScreenState extends State<BackpackItemsScreen> {
  bool _sortByDistance = false;
  Position? _currentPosition;
  bool _loadingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<BackpacksProvider>()
          .loadBackpackItems(widget.backpackId);
    });
  }

  /// Distancia Haversine en metros entre dos puntos
  double _distanceTo(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.toInt()} m';
  }

  Future<void> _toggleSortByDistance() async {
    if (_sortByDistance) {
      setState(() => _sortByDistance = false);
      return;
    }
    setState(() => _loadingLocation = true);
    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));
      setState(() {
        _currentPosition = pos;
        _sortByDistance = true;
        _loadingLocation = false;
      });
    } catch (_) {
      setState(() => _loadingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo obtener tu ubicación')),
        );
      }
    }
  }

  List<BackpackItemModel> _sortedItems(List<BackpackItemModel> items) {
    if (!_sortByDistance || _currentPosition == null) return items;

    return [...items]..sort((a, b) {
        final latA = double.tryParse(a.latitud ?? '');
        final lngA = double.tryParse(a.longitud ?? '');
        final latB = double.tryParse(b.latitud ?? '');
        final lngB = double.tryParse(b.longitud ?? '');

        final hasA = latA != null && lngA != null;
        final hasB = latB != null && lngB != null;

        if (!hasA && !hasB) return 0;
        if (!hasA) return 1; // sin coords van al final
        if (!hasB) return -1;

        final distA = _distanceTo(
            _currentPosition!.latitude, _currentPosition!.longitude, latA, lngA);
        final distB = _distanceTo(
            _currentPosition!.latitude, _currentPosition!.longitude, latB, lngB);
        return distA.compareTo(distB);
      });
  }

  Future<void> _scanAndValidate() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (result == null || !mounted) return;
    final scannedFolio = result.trim();

    // Buscar el ítem por folio escaneado
    final items = context.read<BackpacksProvider>().selectedItems;
    final item = items.cast<BackpackItemModel?>().firstWhere(
          (i) => i?.folioOrden.trim() == scannedFolio,
          orElse: () => null,
        );

    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Folio $scannedFolio no encontrado en esta mochila')),
      );
      return;
    }

    final ok = await context.read<BackpacksProvider>().validateItemByFolio(
      idBackpack: widget.backpackId,
      folio: scannedFolio,
    );
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<BackpacksProvider>().errorMessage ?? 'No se pudo validar la orden',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Orden $scannedFolio validada correctamente')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BackpacksProvider>();
    final items = _sortedItems(provider.selectedItems);
    final canViewOrderInfo = widget.isAdmin || widget.backpackState != 1;

    final allValidated = items.isNotEmpty && items.every((i) => i.isValidated);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ítems de mochila'),
        actions: [
          // Botón ordenar por distancia
          _loadingLocation
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    Icons.sort,
                    color: _sortByDistance ? Colors.amber : null,
                  ),
                  tooltip: _sortByDistance
                      ? 'Quitar orden por distancia'
                      : 'Ordenar por distancia',
                  onPressed: _toggleSortByDistance,
                ),
          if (!widget.isAdmin && canViewOrderInfo)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Escanear',
              onPressed: _scanAndValidate,
            ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Banner de orden activo
                if (_sortByDistance && canViewOrderInfo)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFF1A73E8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.near_me,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Ordenado: más cercano primero',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _sortByDistance = false),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 18),
                        ),
                      ],
                    ),
                  ),

                // Progreso
                if (provider.selectedItems.isNotEmpty && canViewOrderInfo)
                  LinearProgressIndicator(
                    value: provider.selectedItems
                            .where((i) => i.isValidated)
                            .length /
                        provider.selectedItems.length,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                        const AlwaysStoppedAnimation(Colors.green),
                  ),

                Expanded(
                  child: canViewOrderInfo
                      ? ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            double? dist;
                            if (_sortByDistance && _currentPosition != null) {
                              final lat = double.tryParse(items[i].latitud ?? '');
                              final lng = double.tryParse(items[i].longitud ?? '');
                              if (lat != null && lng != null) {
                                dist = _distanceTo(
                                  _currentPosition!.latitude,
                                  _currentPosition!.longitude,
                                  lat,
                                  lng,
                                );
                              }
                            }
                            return _ItemTile(
                              item: items[i],
                              isAdmin: widget.isAdmin,
                              distance: dist != null
                                  ? _formatDistance(dist)
                                  : null,
                              onDelete: widget.isAdmin
                                  ? () => provider
                                      .deleteItem(items[i].idBackpackItem)
                                  : null,
                            );
                          },
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.lock_outline, size: 42, color: Colors.grey),
                                SizedBox(height: 10),
                                Text(
                                  'Acepta la mochila para ver la información de las órdenes.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),

                // Botones de acción (solo mensajero)
                if (!widget.isAdmin)
                  _ActionButtons(
                    backpackId: widget.backpackId,
                    backpackState: widget.backpackState,
                    allValidated: allValidated,
                    provider: provider,
                  ),
              ],
            ),
    );
  }
}

class _ActionButtons extends StatefulWidget {
  final int backpackId;
  final int backpackState;
  final bool allValidated;
  final BackpacksProvider provider;
  const _ActionButtons({
    required this.backpackId,
    required this.backpackState,
    required this.allValidated,
    required this.provider,
  });

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _loading = false;

  Future<void> _changeState(int newState) async {
    if (newState == 3 && !widget.allValidated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes validar todas las entregas antes de finalizar la mochila'),
        ),
      );
      return;
    }

    final label = newState == 2 ? 'aceptar' : 'finalizar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(newState == 2 ? 'Aceptar mochila' : 'Finalizar mochila'),
        content: Text(newState == 2
            ? '¿Confirmas que aceptas esta mochila y empiezas la ruta?'
            : '¿Confirmas que todas las entregas han sido realizadas?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(label[0].toUpperCase() + label.substring(1))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    final updated = await widget.provider.updateState(widget.backpackId, newState);
    if (!mounted) return;
    setState(() => _loading = false);
    if (updated) {
      Navigator.pop(context);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.provider.errorMessage ?? 'No se pudo actualizar la mochila'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // State 1 = Asignada → mostrar "Aceptar mochila"
    // State 2 = En Ruta  → mostrar "Finalizar mochila" (solo si todas validadas)
    if (widget.backpackState == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Aceptar mochila'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: Colors.blue,
          ),
          onPressed: () => _changeState(2),
        ),
      );
    }

    if (widget.backpackState == 2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          icon: const Icon(Icons.flag),
          label: Text(widget.allValidated
              ? 'Finalizar mochila'
              : 'Finalizar mochila (${widget.provider.selectedItems.where((i) => i.isValidated).length}/${widget.provider.selectedItems.length} validadas)'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: widget.allValidated ? Colors.green : Colors.orange,
          ),
          onPressed: widget.allValidated ? () => _changeState(3) : null,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _ItemTile extends StatelessWidget {
  final BackpackItemModel item;
  final bool isAdmin;
  final String? distance;
  final VoidCallback? onDelete;
  const _ItemTile({
    required this.item,
    required this.isAdmin,
    this.distance,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: item.isValidated 
          ? Colors.green.shade50 
          : Colors.white,
      child: ListTile(
        tileColor: item.isValidated 
            ? Colors.green.shade50 
            : null,
        leading: CircleAvatar(
          backgroundColor:
              item.isValidated ? Colors.green.shade100 : Colors.grey.shade100,
          child: Icon(
            item.isValidated ? Icons.check_circle : Icons.radio_button_unchecked,
            color: item.isValidated ? Colors.green : Colors.grey,
            size: 24,
          ),
        ),
        title: Text(
          item.folioOrden,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: item.isValidated ? Colors.green.shade700 : Colors.black,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.nombreCliente,
              style: TextStyle(
                color: item.isValidated ? Colors.green.shade600 : Colors.grey.shade700,
              ),
            ),
            if (distance != null)
              Row(
                children: [
                  const Icon(Icons.near_me,
                      size: 12, color: Color(0xFF1A73E8)),
                  const SizedBox(width: 3),
                  Text(
                    distance!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1A73E8),
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
          ],
        ),
        trailing: isAdmin
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: onDelete,
              )
            : Icon(
                Icons.chevron_right, 
                color: item.isValidated ? Colors.green : Colors.grey,
              ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(orderId: item.idOrdenVenta),
          ),
        ),
      ),
    );
  }
}

/// Pantalla simple de escáner QR
class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  bool _scanned = false;
  bool _showManual = false;
  final _manualCtrl = TextEditingController();

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  void _submitManual() {
    final val = _manualCtrl.text.trim();
    if (val.isEmpty) return;
    if (_scanned) return;
    _scanned = true;
    Navigator.pop(context, val);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear folio'),
        actions: [
          IconButton(
            tooltip: 'Ingresar manualmente',
            icon: Icon(_showManual ? Icons.qr_code_scanner : Icons.keyboard),
            onPressed: () => setState(() => _showManual = !_showManual),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_scanned) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                _scanned = true;
                Navigator.pop(context, barcode!.rawValue);
              }
            },
          ),
          if (_showManual)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualCtrl,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Folio de orden...',
                          hintStyle: TextStyle(color: Colors.white54),
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white54)),
                          focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white)),
                        ),
                        onSubmitted: (_) => _submitManual(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _submitManual,
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
