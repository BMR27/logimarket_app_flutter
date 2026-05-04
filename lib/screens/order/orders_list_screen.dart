import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/backpacks_provider.dart';
import '../../providers/orders_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/order_model.dart';
import '../../services/location_tracking_service.dart';
import 'order_detail_screen.dart';

enum DeliveryFilter { all, pending, enRuta, delivered, incidencias }

const double _kBaseCommissionRate = 0.05;
const double _kDeliveredBonusRate = 0.02;

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  final _searchCtrl = TextEditingController();
  DeliveryFilter _activeFilter = DeliveryFilter.all;
  bool _didInitialLoad = false;

  bool _isAdminOrLeader(AuthProvider auth) {
    final type = auth.user?.type.toLowerCase() ?? '';
    return type == 'admin' || type == 'lider';
  }

  String _normalizeFolio(String value) => value.trim().toUpperCase();

  int _safeParseInt(String value) => int.tryParse(value.trim()) ?? 0;

  bool _isActiveBackpackState(int state) => state == 1 || state == 2;

  Set<int> _activeBackpackOrderIds(BackpacksProvider backpacksProvider) {
    final activeBackpackIds = backpacksProvider.backpacks
        .where((b) => _isActiveBackpackState(b.state))
        .map((b) => b.id)
        .toSet();

    if (kDebugMode) {
      debugPrint(
        '[ENTREGAS] total_backpacks=${backpacksProvider.backpacks.length} '
        'active_bp=${activeBackpackIds.length} '
        'items=${backpacksProvider.selectedItems.length}',
      );
    }

    if (activeBackpackIds.isEmpty) return <int>{};

    final orderIds = backpacksProvider.selectedItems
        .where((i) => activeBackpackIds.contains(i.idBackpack))
        .map((i) => i.idOrdenVenta)
        .toSet();

    if (kDebugMode) {
      debugPrint('[ENTREGAS] filtered_order_ids=${orderIds.length} ids=[${orderIds.take(3).join(",")}...]');
    }

    return orderIds;
  }

  Set<String> _activeBackpackFolios(BackpacksProvider backpacksProvider) {
    final activeBackpackIds = backpacksProvider.backpacks
        .where((b) => _isActiveBackpackState(b.state))
        .map((b) => b.id)
        .toSet();

    if (activeBackpackIds.isEmpty) return <String>{};

    return backpacksProvider.selectedItems
        .where((i) => activeBackpackIds.contains(i.idBackpack))
        .map((i) => _normalizeFolio(i.folioOrden))
        .where((folio) => folio.isNotEmpty)
        .toSet();
  }

  bool _matchesActiveOrder(
    OrderModel order,
    Set<int> activeOrderIds,
    Set<String> activeFolios,
  ) {
    if (activeOrderIds.contains(order.id)) return true;
    if (activeOrderIds.contains(order.idOrdenVenta)) return true;

    final folioNormalized = _normalizeFolio(order.folioOrdenCliente);
    if (activeFolios.contains(folioNormalized)) return true;

    final folioAsInt = _safeParseInt(order.folioOrdenCliente);
    if (folioAsInt > 0 && activeOrderIds.contains(folioAsInt)) return true;

    return false;
  }

  Future<void> _loadOrdersWithEquipos(
    AuthProvider auth,
    OrdersProvider ordersProvider, {
    String folio = '',
  }) async {
    await auth.ensureEquiposLoaded();
    if (!mounted) return;
    final backpacksProvider = context.read<BackpacksProvider>();

    if (auth.user != null && !_isAdminOrLeader(auth)) {
      await backpacksProvider.loadBackpacks(auth.user!.idUsuario);
      if (!mounted) return;

      final activeBackpacks = backpacksProvider.backpacks
          .where((b) => _isActiveBackpackState(b.state))
          .toList();

      if (kDebugMode) {
        debugPrint('[ENTREGAS] _loadOrdersWithEquipos: found ${activeBackpacks.length} active backpacks');
      }

      if (activeBackpacks.isNotEmpty) {
        await backpacksProvider.loadMapItems(
          isAdmin: false,
          userId: auth.user!.idUsuario,
          idRepartidor: activeBackpacks.first.idRepartidor,
          idBackpackIds: activeBackpacks.map((b) => b.id).toList(),
        );
        if (kDebugMode) {
          debugPrint('[ENTREGAS] _loadOrdersWithEquipos: after loadMapItems items=${backpacksProvider.selectedItems.length}');
        }
      }

      final activeOrderIds = _activeBackpackOrderIds(backpacksProvider).toList();
      await ordersProvider.loadOrdersByIds(
        auth.equiposForQuery,
        activeOrderIds,
        folio: folio,
      );
      return;
    }

    await ordersProvider.loadOrders(auth.equiposForQuery, folio: folio);
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didInitialLoad) return;
      _didInitialLoad = true;
      final auth = context.read<AuthProvider>();
      final ordersProvider = context.read<OrdersProvider>();
      _loadOrdersWithEquipos(auth, ordersProvider);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersProvider = context.watch<OrdersProvider>();
    final backpacksProvider = context.watch<BackpacksProvider>();
    final auth = context.watch<AuthProvider>();
    final isAdminOrLeader = _isAdminOrLeader(auth);
    final activeOrderIds = _activeBackpackOrderIds(backpacksProvider);
    final activeFolios = _activeBackpackFolios(backpacksProvider);
    final allOrders = isAdminOrLeader
      ? ordersProvider.orders
      : ordersProvider.orders
        .where((o) => _matchesActiveOrder(o, activeOrderIds, activeFolios))
        .toList();
    if (!isAdminOrLeader && kDebugMode) {
      final orderIds = ordersProvider.orders.map((o) => o.idOrdenVenta).take(3).toList();
      final orderFolios = ordersProvider.orders
          .map((o) => _normalizeFolio(o.folioOrdenCliente))
          .take(3)
          .toList();
      debugPrint(
        '[ENTREGAS] total_orders=${ordersProvider.orders.length} '
        'order_ids_sample=[${orderIds.join(",")}] '
        'order_folios_sample=[${orderFolios.join(",")}] '
        'active_ids=${activeOrderIds.length} '
        'active_ids_sample=[${activeOrderIds.take(3).join(",")}] '
        'active_folios=${activeFolios.length} '
        'filtered=${allOrders.length}',
      );
    }
    final visibleOrders = _buildVisibleOrders(allOrders, _searchCtrl.text, _activeFilter);
    final summary = _buildSummary(allOrders);
    final commissionSummary = _buildCommissionSummary(allOrders);

    return Column(
      children: [
        // Header operativo: búsqueda + resumen + filtros
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar por folio o cliente...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _loadOrdersWithEquipos(auth, ordersProvider);
                          },
                        )
                      : null,
                ),
                onChanged: (v) {
                  if (v.length >= 2) {
                    _loadOrdersWithEquipos(auth, ordersProvider, folio: v);
                  }
                },
              ),
              const SizedBox(height: 12),
              _CommissionBoard(summary: commissionSummary, money: _money),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.local_shipping_outlined,
                      label: 'Pendientes',
                      value: '${summary.pendingCount}',
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.route,
                      label: 'En ruta',
                      value: '${summary.enRutaCount}',
                      color: Colors.cyan,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.check_circle_outline,
                      label: 'Entregadas',
                      value: '${summary.deliveredCount}',
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Comisión estimada del día: ${_money(commissionSummary.payableNow + commissionSummary.pending)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    'Mostrando ${visibleOrders.length} de ${allOrders.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      selected: _activeFilter == DeliveryFilter.all,
                      label: 'Todas',
                      onTap: () => setState(() => _activeFilter = DeliveryFilter.all),
                    ),
                    _FilterChip(
                      selected: _activeFilter == DeliveryFilter.pending,
                      label: 'Pendientes',
                      onTap: () => setState(() => _activeFilter = DeliveryFilter.pending),
                    ),
                    _FilterChip(
                      selected: _activeFilter == DeliveryFilter.enRuta,
                      label: 'En ruta',
                      onTap: () => setState(() => _activeFilter = DeliveryFilter.enRuta),
                    ),
                    _FilterChip(
                      selected: _activeFilter == DeliveryFilter.delivered,
                      label: 'Entregadas',
                      onTap: () => setState(() => _activeFilter = DeliveryFilter.delivered),
                    ),
                    _FilterChip(
                      selected: _activeFilter == DeliveryFilter.incidencias,
                      label: 'Incidencias',
                      onTap: () => setState(() => _activeFilter = DeliveryFilter.incidencias),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Banner de conectividad
        if (ordersProvider.offline)
          Container(
            color: Colors.orange.shade100,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.cloud_off, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Sin conexión — mostrando datos guardados',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => _loadOrdersWithEquipos(auth, ordersProvider),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reintentar',
                      style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
                ),
              ],
            ),
          ),

        // Lista
        Expanded(
          child: ordersProvider.loading
              ? _buildShimmer()
              : RefreshIndicator(
                  onRefresh: () => _loadOrdersWithEquipos(auth, ordersProvider),
                  child: visibleOrders.isEmpty
                      ? _buildEmptyState(
                          context,
                          ordersProvider,
                          auth,
                          allOrders.isEmpty,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: visibleOrders.length,
                          itemBuilder: (ctx, i) =>
                              _OrderCard(
                          order: visibleOrders[i],
                          commission: _estimatedCommission(visibleOrders[i]),
                          isDelivered: _isDelivered(visibleOrders[i].idStatus),
                          isIncidencia: _isIncidencia(visibleOrders[i].idStatus),
                              ),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    OrdersProvider ordersProvider,
    AuthProvider auth,
    bool allEmpty,
  ) {
    final hasError = ordersProvider.errorMessage != null;
    final hasFilter = _activeFilter != DeliveryFilter.all || _searchCtrl.text.isNotEmpty;

    return ListView(
      children: [
        const SizedBox(height: 60),
        Column(
          children: [
            Icon(
              hasError ? Icons.cloud_off_outlined : Icons.inbox_outlined,
              size: 64,
              color: hasError ? Colors.orange : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              hasError
                  ? 'No se pudieron cargar las entregas'
                  : hasFilter
                      ? 'Sin resultados para el filtro seleccionado'
                      : 'No hay entregas disponibles',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (ordersProvider.errorMessage != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  ordersProvider.errorMessage!,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (hasError || allEmpty)
              FilledButton.icon(
                onPressed: () => _loadOrdersWithEquipos(auth, ordersProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            if (hasFilter && !allEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _activeFilter = DeliveryFilter.all;
                  _searchCtrl.clear();
                }),
                child: const Text('Quitar filtros'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  _OrdersSummary _buildSummary(List<OrderModel> orders) {
    int pendingCount = 0;
    int enRutaCount = 0;
    int deliveredCount = 0;
    double totalAmount = 0;

    for (final o in orders) {
      totalAmount += o.total;
      if (_isDelivered(o.idStatus)) {
        deliveredCount++;
      } else if (_isEnRuta(o.idStatus)) {
        enRutaCount++;
      } else {
        pendingCount++;
      }
    }

    return _OrdersSummary(
      pendingCount: pendingCount,
      enRutaCount: enRutaCount,
      deliveredCount: deliveredCount,
      totalAmount: totalAmount,
    );
  }

  List<OrderModel> _buildVisibleOrders(
    List<OrderModel> orders,
    String query,
    DeliveryFilter filter,
  ) {
    final q = query.trim().toLowerCase();

    bool matchesFilter(OrderModel o) {
      switch (filter) {
        case DeliveryFilter.all:
          return true;
        case DeliveryFilter.pending:
          return !_isDelivered(o.idStatus) && !_isIncidencia(o.idStatus);
        case DeliveryFilter.enRuta:
          return _isEnRuta(o.idStatus);
        case DeliveryFilter.delivered:
          return _isDelivered(o.idStatus);
        case DeliveryFilter.incidencias:
          return _isIncidencia(o.idStatus);
      }
    }

    bool matchesQuery(OrderModel o) {
      if (q.isEmpty) return true;
      return o.folioOrdenCliente.toLowerCase().contains(q) ||
          o.cliente.toLowerCase().contains(q);
    }

    final filtered = orders.where((o) => matchesFilter(o) && matchesQuery(o)).toList();
    filtered.sort((a, b) {
      final aRank = _priorityRank(a.idStatus);
      final bRank = _priorityRank(b.idStatus);
      if (aRank != bRank) return aRank.compareTo(bRank);
      return b.id.compareTo(a.id);
    });
    return filtered;
  }

  bool _isDelivered(int status) => status == 1;
  bool _isEnRuta(int status) => status == 3 || status == 7;
  bool _isIncidencia(int status) => status == 4 || status == 5 || status == 6;

  double _baseCommission(OrderModel order) {
    if (_isIncidencia(order.idStatus)) return 0;
    return order.total * _kBaseCommissionRate;
  }

  double _bonusCommission(OrderModel order) {
    if (!_isDelivered(order.idStatus)) return 0;
    return order.total * _kDeliveredBonusRate;
  }

  double _estimatedCommission(OrderModel order) {
    if (_isIncidencia(order.idStatus)) return 0;
    return _baseCommission(order) + _bonusCommission(order);
  }

  int _priorityRank(int status) {
    if (_isEnRuta(status)) return 0;
    if (!_isDelivered(status) && !_isIncidencia(status)) return 1;
    if (_isIncidencia(status)) return 2;
    return 3;
  }

  String _money(double amount) {
    return '\$${amount.toStringAsFixed(2)}';
  }

  _CommissionSummary _buildCommissionSummary(List<OrderModel> orders) {
    double payableNow = 0;
    double pending = 0;
    double riskAmount = 0;
    double baseTotal = 0;
    double bonusTotal = 0;

    for (final o in orders) {
      final base = _baseCommission(o);
      final bonus = _bonusCommission(o);
      final total = base + bonus;

      baseTotal += base;
      bonusTotal += bonus;

      if (_isIncidencia(o.idStatus)) {
        riskAmount += o.total;
        continue;
      }

      if (_isDelivered(o.idStatus)) {
        payableNow += total;
      } else {
        pending += total;
      }
    }

    return _CommissionSummary(
      payableNow: payableNow,
      pending: pending,
      riskAmount: riskAmount,
      baseTotal: baseTotal,
      bonusTotal: bonusTotal,
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final double commission;
  final bool isDelivered;
  final bool isIncidencia;

  const _OrderCard({
    required this.order,
    required this.commission,
    required this.isDelivered,
    required this.isIncidencia,
  });

  Color _statusColor(int status) {
    switch (status) {
      case 1: return Colors.green;
      case 2: return Colors.blue;
      case 3: return Colors.orange;
      case 4: return Colors.red;
      case 5: return Colors.purple;
      case 7: return Colors.cyan.shade700; // On Delivery
      default: return Colors.grey;
  }
  }

  bool get _isActiveDelivery {
    final tracker = LocationTrackingService.instance;
    return tracker.isTracking && tracker.enViaje && tracker.activeOrderId == order.id;
  }

  @override
  Widget build(BuildContext context) {
    final isActiveDelivery = _isActiveDelivery;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isActiveDelivery ? Colors.cyan.shade50 : null,
      shape: isActiveDelivery
          ? RoundedRectangleBorder(
              side: BorderSide(color: Colors.cyan.shade700, width: 2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: ListTile(
        isThreeLine: true,
        contentPadding: const EdgeInsets.all(12),
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              backgroundColor: _statusColor(order.idStatus).withOpacity(0.15),
              child: Icon(Icons.inventory_2, color: _statusColor(order.idStatus)),
            ),
            if (isActiveDelivery)
              const CircleAvatar(
                radius: 7,
                backgroundColor: Colors.white,
                child: CircleAvatar(
                  radius: 5,
                  backgroundColor: Colors.cyan,
                ),
              ),
          ],
        ),
        title: Text(
          order.folioOrdenCliente,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(order.cliente, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(order.idStatus).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusColor(order.idStatus).withOpacity(0.4)),
                  ),
                  child: Text(
                    order.statusOrden,
                    style: TextStyle(
                      fontSize: 11,
                      color: _statusColor(order.idStatus),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isActiveDelivery) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.cyan.shade700.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on, size: 11, color: Colors.cyan.shade700),
                        const SizedBox(width: 3),
                        Text('En Viaje', style: TextStyle(fontSize: 11, color: Colors.cyan.shade700, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isIncidencia
                  ? 'Comisión en riesgo por incidencia'
                  : isDelivered
                      ? 'Comisión acreditable: \$${commission.toStringAsFixed(2)}'
                      : 'Comisión pendiente: \$${commission.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 11,
                color: isIncidencia
                    ? Colors.red.shade400
                    : isDelivered
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '\$${order.total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Com. \$${commission.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)),
        ).then((_) => (context as Element).markNeedsBuild()),
      ),
    );
  }

}

class _OrdersSummary {
  final int pendingCount;
  final int enRutaCount;
  final int deliveredCount;
  final double totalAmount;

  _OrdersSummary({
    required this.pendingCount,
    required this.enRutaCount,
    required this.deliveredCount,
    required this.totalAmount,
  });
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommissionSummary {
  final double payableNow;
  final double pending;
  final double riskAmount;
  final double baseTotal;
  final double bonusTotal;

  _CommissionSummary({
    required this.payableNow,
    required this.pending,
    required this.riskAmount,
    required this.baseTotal,
    required this.bonusTotal,
  });
}

class _CommissionBoard extends StatelessWidget {
  final _CommissionSummary summary;
  final String Function(double) money;

  const _CommissionBoard({required this.summary, required this.money});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Control de Comisiones',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Cobrable hoy: ${money(summary.payableNow)}',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pendiente: ${money(summary.pending)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  'Bono: ${money(summary.bonusTotal)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  'Riesgo: ${money(summary.riskAmount)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Base generada: ${money(summary.baseTotal)}',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _FilterChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
