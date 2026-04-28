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

    await ordersProvider.loadOrders(auth.equiposForQuery);
    if (auth.user != null) {
      await backpacksProvider.loadBackpacks(auth.user!.idUsuario);
    }
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
      body: tabs[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Mapa'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Pedidos'),
          NavigationDestination(
              icon: Icon(Icons.backpack), label: 'Mochilas'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }
}
