import 'package:flutter/material.dart';
import 'dart:async';
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
  Widget _buildInlineNotice(String message, VoidCallback onRetry) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: Colors.orange.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message, VoidCallback onRetry) {
    final isSessionMessage = message.toLowerCase().contains('sesión');
    final title = isSessionMessage ? 'Sesión finalizada' : 'Ocurrió un problema';

    return ListView(
      children: [
        const SizedBox(height: 56),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.red.shade100),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 34,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Reintentar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BackpacksProvider>();
    final auth = context.watch<AuthProvider>();
    final hasBackpacks = provider.backpacks.isNotEmpty;
    final hasError = provider.errorMessage != null;
    final showBlockingError = hasError && !hasBackpacks;
    final showInlineNotice = hasError && hasBackpacks;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => provider.loadBackpacks(auth.user!.idUsuario),
        child: provider.loadingBackpacks
            ? _buildShimmer()
            : showBlockingError
                ? _buildErrorState(
                    provider.errorMessage!,
                    () => provider.loadBackpacks(auth.user!.idUsuario),
                  )
                : !hasBackpacks
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
                        itemCount: provider.backpacks.length + (showInlineNotice ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (showInlineNotice && i == 0) {
                            return _buildInlineNotice(
                              provider.errorMessage!,
                              () => provider.loadBackpacks(auth.user!.idUsuario),
                            );
                          }
                          final dataIndex = i - (showInlineNotice ? 1 : 0);
                          return _BackpackCard(
                            backpack: provider.backpacks[dataIndex],
                            isAdmin: widget.isAdmin,
                          );
                        },
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
      case 4: return 'Cerrada';
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
            ? () {
                unawaited(
                  context.read<BackpacksProvider>().prefetchBackpackItems(backpack.id),
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BackpackItemsScreen(
                      backpackId: backpack.id,
                      isAdmin: isAdmin,
                      backpackState: backpack.state,
                    ),
                  ),
                );
              }
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
