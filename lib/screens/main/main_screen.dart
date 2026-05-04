import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/orders_provider.dart';
import '../../providers/backpacks_provider.dart';
import '../../providers/map_navigation_provider.dart';
import '../order/orders_list_screen.dart';
import '../backpacks/backpacks_screen.dart';
import '../profile/profile_screen.dart';
import 'map_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _prevIndex = 0;

  bool _isAdminOrLeader(AuthProvider auth) {
    final type = auth.user?.type.toLowerCase() ?? '';
    return type == 'admin' || type == 'lider';
  }

  bool _isActiveBackpackState(int state) => state == 1 || state == 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
      context.read<MapNavigationProvider>().addListener(_onMapNavChanged);
    });
  }

  void _onMapNavChanged() {
    final nav = context.read<MapNavigationProvider>();
    if (nav.destination != null && _currentIndex != 0) {
      setState(() => _currentIndex = 0);
    }
  }

  @override
  void dispose() {
    context.read<MapNavigationProvider>().removeListener(_onMapNavChanged);
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final auth = context.read<AuthProvider>();
    final ordersProvider = context.read<OrdersProvider>();
    final backpacksProvider = context.read<BackpacksProvider>();

    await auth.ensureEquiposLoaded();
    await ordersProvider.loadOrders(auth.equiposForQuery);
    if (auth.user != null) {
      await backpacksProvider.loadBackpacks(auth.user!.idUsuario);
      final isAdmin = _isAdminOrLeader(auth);
      final activeBackpacks = backpacksProvider.backpacks
          .where((b) => _isActiveBackpackState(b.state))
          .toList();
      final primaryBackpack = activeBackpacks.isNotEmpty
          ? activeBackpacks.first
          : (backpacksProvider.backpacks.isNotEmpty ? backpacksProvider.backpacks.first : null);
      if (!isAdmin) {
        await backpacksProvider.loadMapItems(
          isAdmin: isAdmin,
          userId: auth.user!.idUsuario,
          idBackpack: primaryBackpack?.id,
          idRepartidor: primaryBackpack?.idRepartidor,
          idBackpackIds: activeBackpacks.map((b) => b.id).toList(),
        );
      }
    }
  }

  Future<void> _reloadOrders() async {
    final auth = context.read<AuthProvider>();
    final ordersProvider = context.read<OrdersProvider>();
    final backpacksProvider = context.read<BackpacksProvider>();
    await auth.ensureEquiposLoaded();

    if (!mounted) return;

    if (auth.user != null && !_isAdminOrLeader(auth)) {
      await backpacksProvider.loadBackpacks(auth.user!.idUsuario);
      if (!mounted) return;
      final activeBackpacks = backpacksProvider.backpacks
          .where((b) => _isActiveBackpackState(b.state))
          .toList();

      if (activeBackpacks.isEmpty) {
        await ordersProvider.loadOrdersByIds(auth.equiposForQuery, const <int>[]);
        return;
      }

      if (activeBackpacks.isNotEmpty) {
        await backpacksProvider.loadMapItems(
          isAdmin: false,
          userId: auth.user!.idUsuario,
          idBackpack: activeBackpacks.first.id,
          idRepartidor: activeBackpacks.first.idRepartidor,
          idBackpackIds: activeBackpacks.map((b) => b.id).toList(),
        );
      }

      final activeBackpackIds = activeBackpacks.map((b) => b.id).toSet();
      final activeOrderIds = backpacksProvider.selectedItems
          .where((i) => activeBackpackIds.contains(i.idBackpack))
          .map((i) => i.idOrdenVenta)
          .where((id) => id > 0)
          .toSet()
          .toList();

      await ordersProvider.loadOrdersByIds(auth.equiposForQuery, activeOrderIds);
      return;
    }

    if (!mounted) return;
    await ordersProvider.loadOrders(auth.equiposForQuery);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.user?.type.toLowerCase() == 'admin' ||
        auth.user?.type.toLowerCase() == 'lider';

    final tabs = [
      const MapTab(),
      const OrdersListScreen(),
      BackpacksScreen(isAdmin: isAdmin),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logimarket'),
        actions: [
          // Indicador de modo offline
          Consumer<OrdersProvider>(
            builder: (_, ordProv, __) => ordProv.offline
                ? const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.cloud_off, color: Colors.orange),
                  )
                : const SizedBox.shrink(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'sync') {
                final count =
                    await context.read<OrdersProvider>().syncOfflineOrders();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$count pedidos sincronizados')),
                  );
                }
              } else if (value == 'logout') {
                await context.read<AuthProvider>().logout();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'sync', child: Text('Sincronizar offline')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() {
            _prevIndex = _currentIndex;
            _currentIndex = i;
          });
          // Tab Entregas (index 1): recargar datos al entrar
          if (i == 1 && _prevIndex != 1) {
            _reloadOrders();
          }
        },
      destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Mapa'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Entregas'),
          NavigationDestination(
              icon: Icon(Icons.backpack), label: 'Mochilas'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }
}
