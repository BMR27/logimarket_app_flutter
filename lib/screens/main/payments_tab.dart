import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/orders_provider.dart';
import '../../services/api_service.dart';
import '../../services/payments_service.dart';

class PaymentsTab extends StatefulWidget {
  const PaymentsTab({super.key});

  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<PaymentsTab> {
  final PaymentsService _paymentsService = PaymentsService();
  int? _selectedOrderId;
  Map<String, dynamic>? _payment;
  bool _loading = false;
  bool _cashLoading = false;
  bool _cashPaid = false;
  String? _error;
  Timer? _pollTimer;

  static const _prefPrefix = 'cash_paid_';

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Persistencia efectivo ─────────────────────────────────────────
  Future<void> _loadCashState(int orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('$_prefPrefix$orderId') ?? false;
    if (mounted) setState(() => _cashPaid = saved);
  }

  Future<void> _saveCashState(int orderId, bool paid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefPrefix$orderId', paid);
  }

  // ── Efectivo ──────────────────────────────────────────────────────
  Future<void> _confirmCashPayment() async {
    if (_selectedOrderId == null) {
      setState(() => _error = 'Selecciona una orden primero');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar pago en efectivo'),
        content: const Text('¿El cliente pagó en efectivo? Esta acción se guardará.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cashLoading = true);
    await _saveCashState(_selectedOrderId!, true);
    if (!mounted) return;
    setState(() {
      _cashPaid = true;
      _cashLoading = false;
      _payment = null; // limpia el QR si había uno activo
      _error = null;
    });
    _pollTimer?.cancel();
  }

  Future<void> _clearCashPayment() async {
    if (_selectedOrderId == null) return;
    await _saveCashState(_selectedOrderId!, false);
    if (!mounted) return;
    setState(() => _cashPaid = false);
  }

  Future<void> _generateQr() async {
    if (_selectedOrderId == null) {
      setState(() => _error = 'Selecciona una orden primero');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final payment = await _paymentsService.generatePayment(_selectedOrderId!);
      if (!mounted) return;
      setState(() {
        _payment = payment;
        _loading = false;
      });
      _startPolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo generar el pago: $e';
      });
    }
  }

  Future<void> _refreshStatus() async {
    if (_selectedOrderId == null) return;

    try {
      final payment = await _paymentsService.getPaymentStatus(_selectedOrderId!);
      if (!mounted) return;
      setState(() {
        _payment = {
          ...?_payment,
          ...payment,
        };
      });

      final status = (_payment?['paymentStatus'] ?? '').toString().toUpperCase();
      if (status == 'PAID' || status == 'FAILED' || status == 'EXPIRED' || status == 'CANCELLED') {
        _pollTimer?.cancel();
      }
    } catch (_) {
      // Polling silencioso.
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshStatus();
    });
  }

  Future<void> _openCheckout() async {
    final raw = _payment?['checkoutUrl']?.toString() ?? '';
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyText(String text) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Texto copiado')),
    );
  }

  String _formatCurrency(num value, String currency) {
    return '${value.toStringAsFixed(2)} $currency';
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return 'Pago confirmado';
      case 'EXPIRED':
        return 'Este pago expiro';
      case 'FAILED':
        return 'El pago fue rechazado';
      case 'CANCELLED':
        return 'Pago cancelado';
      default:
        return 'Esperando pago';
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return Colors.green;
      case 'EXPIRED':
        return Colors.orange;
      case 'FAILED':
      case 'CANCELLED':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final ordersProvider = context.watch<OrdersProvider>();
    // Deduplicar por id para evitar crash en el Dropdown cuando hay órdenes repetidas
    final _seen = <int>{};
    final orders = List<OrderModel>.from(ordersProvider.orders)
      ..sort((a, b) => b.id.compareTo(a.id));
    final uniqueOrders = orders.where((o) => _seen.add(o.id)).toList();

    final selected = uniqueOrders.where((o) => o.id == _selectedOrderId).cast<OrderModel?>().firstOrNull;
    final status = (_payment?['paymentStatus'] ?? 'WAITING_PAYMENT').toString();
    final amount = num.tryParse((_payment?['amount'] ?? selected?.total ?? 0).toString()) ?? 0;
    final currency = (_payment?['currency'] ?? 'MXN').toString();
    final canDeliver = _cashPaid || _payment?['canDeliver'] == true || status.toUpperCase() == 'PAID';
    final bankTransfer = _payment?['bankTransfer'] is Map<String, dynamic>
      ? Map<String, dynamic>.from(_payment!['bankTransfer'] as Map)
      : null;
    final destinationAccount = (bankTransfer?['destinationAccount'] ?? '').toString();
    final transferReference = (bankTransfer?['reference'] ?? '').toString();
    final transferConcept = (bankTransfer?['concept'] ?? '').toString();
    final transferInstructions = (bankTransfer?['instructions'] is List)
      ? List<String>.from(bankTransfer!['instructions'] as List)
      : const <String>[];

    return RefreshIndicator(
      onRefresh: () async {
        await ordersProvider.loadOrders(auth.equiposForQuery);
        await _refreshStatus();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Cobro por transferencia',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Comparte la cuenta y la referencia para que el cliente transfiera manualmente.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            isExpanded: true,
            value: _selectedOrderId,
            decoration: const InputDecoration(
              labelText: 'Orden',
              border: OutlineInputBorder(),
            ),
            items: uniqueOrders
                .map((o) => DropdownMenuItem<int>(
                      value: o.id,
                      child: Text(
                        '${o.folioOrdenCliente} - ${o.cliente}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedOrderId = value;
                _payment = null;
                _cashPaid = false;
                _error = null;
              });
              _pollTimer?.cancel();
              if (value != null) _loadCashState(value);
            },
          ),
          const SizedBox(height: 12),
          // ── Botones de método de pago ─────────────────────────────
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_loading || _cashPaid) ? null : _generateQr,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.qr_code_2),
                  label: const Text('Generar QR'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _cashPaid ? Colors.green : Colors.green.shade700,
                  ),
                  onPressed: (_cashLoading || _cashPaid) ? null : _confirmCashPayment,
                  icon: _cashLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.payments_outlined),
                  label: Text(_cashPaid ? 'Cobrado' : 'Efectivo'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_cashPaid) ...[
            const SizedBox(height: 18),
            Card(
              color: Colors.green.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.green.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Pago en efectivo registrado',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Guía: ${selected?.folioOrdenCliente ?? '-'}'),
                    Text('Cliente: ${selected?.cliente ?? '-'}'),
                    Text(
                      'Monto: \$${selected?.total.toStringAsFixed(2) ?? '-'} MXN',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Pago confirmado. Ya puedes entregar el paquete.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                        child: const Text('Entregar paquete'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _clearCashPayment,
                        child: Text(
                          'Deshacer pago en efectivo',
                          style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (!_cashPaid && _payment != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Guia: ${selected?.folioOrdenCliente ?? '-'}'),
                    Text('Cliente: ${selected?.cliente ?? '-'}'),
                    Text('Monto: ${_formatCurrency(amount, currency)}'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Estado: '),
                        Text(
                          _statusLabel(status),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _statusColor(status),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if ((_payment?['expiresAt'] ?? '').toString().isNotEmpty)
                      Text('Expira: ${_payment?['expiresAt']}'),
                    if (destinationAccount.isNotEmpty || transferReference.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Datos de transferencia',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (destinationAccount.isNotEmpty)
                        InkWell(
                          onTap: () => _copyText(destinationAccount),
                          child: Text('Cuenta destino: $destinationAccount'),
                        ),
                      if (transferReference.isNotEmpty)
                        InkWell(
                          onTap: () => _copyText(transferReference),
                          child: Text('Referencia: $transferReference'),
                        ),
                      if (transferConcept.isNotEmpty)
                        Text('Concepto: $transferConcept'),
                      if (transferInstructions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...transferInstructions.map((line) => Text('• $line')),
                      ],
                    ],
                    const SizedBox(height: 10),
                    if (bankTransfer == null && (_payment?['qrCodeUrl'] ?? '').toString().isNotEmpty)
                      Center(
                        child: Image.network(
                          _payment!['qrCodeUrl'].toString(),
                          width: 220,
                          height: 220,
                          errorBuilder: (_, __, ___) => const Text('No se pudo cargar QR'),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (bankTransfer == null)
                          OutlinedButton.icon(
                            onPressed: _openCheckout,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Abrir checkout'),
                          ),
                        OutlinedButton.icon(
                          onPressed: _refreshStatus,
                          icon: const Icon(Icons.sync),
                          label: const Text('Actualizar estado'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: canDeliver ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pago confirmado. Ya puedes entregar el paquete.')),
                          );
                        } : null,
                        child: const Text('Entregar paquete'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension _FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
