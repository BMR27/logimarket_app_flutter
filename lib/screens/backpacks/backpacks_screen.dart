import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/backpacks_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/backpack_model.dart';
import '../../utils/app_theme.dart';
import 'backpack_items_screen.dart';
import 'backpack_creator_screen.dart';

class BackpacksScreen extends StatefulWidget {
  final bool isAdmin;
  const BackpacksScreen({super.key, required this.isAdmin});

  @override
  State<BackpacksScreen> createState() => _BackpacksScreenState();
}

class _BackpacksScreenState extends State<BackpacksScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BackpacksProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => provider.loadBackpacks(auth.user!.idUsuario),
        child: provider.loading
            ? _buildShimmer()
            : provider.errorMessage != null
                ? ListView(
                    children: [
                      const SizedBox(height: 60),
                      Center(
                        child: Column(
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: Colors.red),
                            const SizedBox(height: 12),
                            Text(provider.errorMessage!,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () =>
                                  provider.loadBackpacks(auth.user!.idUsuario),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : provider.backpacks.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 60),
                          const Center(
                            child: Column(
                              children: [
                                Icon(Icons.backpack_outlined,
                                    size: 56, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('Sin mochilas asignadas',
                                    style: TextStyle(color: Colors.grey)),
                                SizedBox(height: 6),
                                Text('Desliza hacia abajo para actualizar',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: provider.backpacks.length,
                        itemBuilder: (_, i) => _BackpackCard(
                          backpack: provider.backpacks[i],
                          isAdmin: widget.isAdmin,
                        ),
                      ),
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Crear mochila'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BackpackCreatorScreen()),
              ),
            )
          : null,
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 4,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _BackpackCard extends StatelessWidget {
  final BackpackModel backpack;
  final bool isAdmin;
  const _BackpackCard({required this.backpack, required this.isAdmin});

  String _stateName(int state) {
    switch (state) {
      case 1: return 'Asignada';
      case 2: return 'En Ruta';
      case 3: return 'Terminada';
      case 4: return 'Cancelada';
      default: return 'Desconocido';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateColor = AppColors.forBackpackState(backpack.state);
    final canOpenDetails = backpack.state != 3;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canOpenDetails
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BackpackItemsScreen(
                      backpackId: backpack.id,
                      isAdmin: isAdmin,
                      backpackState: backpack.state,
                    ),
                  ),
                )
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('La mochila terminada no permite ver órdenes'),
                  ),
                );
              },
        child: Opacity(
          opacity: canOpenDetails ? 1.0 : 0.75,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      backpack.nombreRepartidor,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: stateColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: stateColor.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: stateColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _stateName(backpack.state),
                            style: TextStyle(
                                color: stateColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: backpack.progressPercent,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(stateColor),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
                const SizedBox(height: 6),
                Text(
                  '${backpack.progressOrders}/${backpack.totalOrders} pedidos',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),

                if (!canOpenDetails) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'No disponible: mochila terminada',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],

                // Cambiar estado (solo admin)
                if (isAdmin) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _StateButton(
                          label: 'En Ruta',
                          color: Colors.orange,
                          onTap: () => context
                              .read<BackpacksProvider>()
                              .updateState(backpack.id, 2)),
                      const SizedBox(width: 8),
                      _StateButton(
                          label: 'Terminada',
                          color: Colors.green,
                          onTap: () => context
                              .read<BackpacksProvider>()
                              .updateState(backpack.id, 3)),
                      const SizedBox(width: 8),
                      _StateButton(
                          label: 'Cancelar',
                          color: Colors.red,
                          onTap: () => context
                              .read<BackpacksProvider>()
                              .updateState(backpack.id, 4)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StateButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _StateButton(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
