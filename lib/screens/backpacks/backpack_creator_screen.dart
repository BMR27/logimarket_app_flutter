import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/backpacks_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/backpacks_service.dart';

class BackpackCreatorScreen extends StatefulWidget {
  const BackpackCreatorScreen({super.key});

  @override
  State<BackpackCreatorScreen> createState() => _BackpackCreatorScreenState();
}

class _BackpackCreatorScreenState extends State<BackpackCreatorScreen> {
  // Paso 1: seleccionar repartidor
  final _repartidorCtrl = TextEditingController();
  Map<String, dynamic>? _selectedRepartidor;
  List<Map<String, dynamic>> _repartidorResults = [];

  // Paso 2: agregar órdenes
  final List<Map<String, dynamic>> _selectedOrders = [];
  bool _step2 = false;
  bool _loading = false;
  final _service = BackpacksService();

  @override
  void dispose() {
    _repartidorCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchRepartidores(String nombre) async {
    if (nombre.length < 2) return;
    final auth = context.read<AuthProvider>();
    try {
      final results = await _service.searchRepartidores(
        equipos: auth.equiposForQuery,
        nombre: nombre,
      );
      if (!mounted) return;
      setState(() => _repartidorResults = results);
    } catch (_) {}
  }

  Future<void> _scanAndAddOrder() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (result == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    final equipos = auth.equiposForQuery;
    // Verificar que el folio existe
    try {
      final results = await _service.searchOrders(
        equipos: equipos,
        folio: result,
      );
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folio $result no encontrado')),
        );
        return;
      }
      final order = results.first;
      if (_selectedOrders.any((o) => o['Id'] == order['Id'])) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta orden ya fue agregada')),
        );
        return;
      }
      setState(() => _selectedOrders.add(order));
    } catch (_) {}
  }

  Future<void> _createBackpack() async {
    if (_selectedRepartidor == null || _selectedOrders.isEmpty) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final orderIds =
        _selectedOrders.map((o) => o['Id'] as int).toList();

    final ok = await context.read<BackpacksProvider>().createBackpack(
          idRepartidor: _selectedRepartidor!['Id'] as int,
          idLider: auth.user!.idUsuario,
          orderIds: orderIds,
        );

    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Mochila creada exitosamente' : 'Error al crear mochila'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ));
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step2 ? 'Agregar órdenes' : 'Seleccionar repartidor'),
      ),
      body: _step2 ? _buildStep2() : _buildStep1(),
    );
  }

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _repartidorCtrl,
            decoration: const InputDecoration(
              labelText: 'Buscar repartidor por nombre',
              prefixIcon: Icon(Icons.person_search),
            ),
            onChanged: _searchRepartidores,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _repartidorResults.length,
              itemBuilder: (_, i) {
                final r = _repartidorResults[i];
                final name =
                    '${r['Nombres']} ${r['ApellidoPaterno']} ${r['ApellidoMaterno']}'
                        .trim();
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(name),
                  selected: _selectedRepartidor?['Id'] == r['Id'],
                  selectedTileColor: Colors.blue.shade50,
                  onTap: () => setState(() => _selectedRepartidor = r),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: _selectedRepartidor == null
                ? null
                : () => setState(() => _step2 = true),
            child: const Text('Continuar →'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Repartidor seleccionado
          Card(
            color: Colors.blue.shade50,
            child: ListTile(
              leading: const Icon(Icons.person, color: Colors.blue),
              title: Text(
                '${_selectedRepartidor!['Nombres']} ${_selectedRepartidor!['ApellidoPaterno']}'
                    .trim(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Repartidor seleccionado'),
            ),
          ),
          const SizedBox(height: 16),

          // Órdenes agregadas
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_selectedOrders.length} órdenes',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Escanear'),
                      onPressed: _scanAndAddOrder,
                    ),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _selectedOrders.length,
                    itemBuilder: (_, i) {
                      final o = _selectedOrders[i];
                      return ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(o['Folio'] ?? ''),
                        subtitle: Text(o['Cliente'] ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red),
                          onPressed: () =>
                              setState(() => _selectedOrders.removeAt(i)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          ElevatedButton.icon(
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.backpack),
            label: const Text('Crear mochila'),
            onPressed: (_loading || _selectedOrders.isEmpty) ? null : _createBackpack,
          ),
        ],
      ),
    );
  }
}

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
