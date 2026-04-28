import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../config/api_config.dart';
import '../../utils/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uiSoundEnabled = true;
  double _uiVolume = 0.7;
  bool _codebarSoundEnabled = true;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _uiSoundEnabled = _prefs!.getBool('uiSoundEnabled') ?? true;
      _uiVolume = _prefs!.getDouble('uiVolume') ?? 0.7;
      _codebarSoundEnabled = _prefs!.getBool('codebarSoundEnabled') ?? true;
    });
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resetear asignaciones'),
        content: const Text(
            '¿Seguro? Esto cancelará todas las mochilas activas y liberará sus órdenes para volver a asignarlas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Resetear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final result = await ApiService().post(ApiConfig.adminReset, {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${result['backpacksCancelled']} mochilas canceladas · ${result['ordersReset']} órdenes liberadas'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final equipos = auth.equipos;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Avatar + nombre ──────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    user != null && user.nombres.isNotEmpty
                        ? user.nombres[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.fullName ?? '—',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.correo ?? '—',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _typeLabel(user?.type ?? ''),
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── Equipos asignados ─────────────────────────────────────────
        if (equipos.isNotEmpty) ...[
          _SectionHeader(title: 'Equipos asignados'),
          Card(
            child: Column(
              children: equipos
                  .map((e) => ListTile(
                        leading:
                            const Icon(Icons.group, color: Colors.blueGrey),
                        title: Text(e.equipo),
                        subtitle: Text(e.nomenclatura),
                        trailing: e.lider
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text('Líder',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold)),
                              )
                            : null,
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Sonidos de UI ─────────────────────────────────────────────
        _SectionHeader(title: 'Sonidos de interfaz'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Sonidos de UI'),
                subtitle:
                    const Text('Activar sonidos al interactuar con la app'),
                value: _uiSoundEnabled,
                onChanged: (v) {
                  setState(() => _uiSoundEnabled = v);
                  _prefs?.setBool('uiSoundEnabled', v);
                },
              ),
              if (_uiSoundEnabled)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.volume_down, color: Colors.grey),
                      Expanded(
                        child: Slider(
                          value: _uiVolume,
                          onChanged: (v) {
                            setState(() => _uiVolume = v);
                            _prefs?.setDouble('uiVolume', v);
                          },
                        ),
                      ),
                      const Icon(Icons.volume_up, color: Colors.grey),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Escáner ───────────────────────────────────────────────────
        _SectionHeader(title: 'Escáner de códigos'),
        Card(
          child: SwitchListTile(
            title: const Text('Sonido del escáner'),
            subtitle:
                const Text('Reproducir sonido al escanear un código'),
            value: _codebarSoundEnabled,
            onChanged: (v) {
              setState(() => _codebarSoundEnabled = v);
              _prefs?.setBool('codebarSoundEnabled', v);
            },
          ),
        ),

        const SizedBox(height: 12),

        // ── Acerca de ─────────────────────────────────────────────────
        _SectionHeader(title: 'Acerca de'),
        Card(
          child: Column(
            children: const [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Versión'),
                trailing:
                    Text('1.0.0', style: TextStyle(color: Colors.grey)),
              ),
              Divider(height: 0),
              ListTile(
                leading: Icon(Icons.business),
                title: Text('Desarrollado por'),
                trailing: Text('Quantum Nest',
                    style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Acciones admin ────────────────────────────────────────────
        if (user != null &&
            (user.type.toLowerCase() == 'admin' ||
                user.type.toLowerCase() == 'lider')) ...
          [
            _SectionHeader(title: 'Administración'),
            OutlinedButton.icon(
              onPressed: _confirmReset,
              icon: const Icon(Icons.restart_alt, color: Colors.orange),
              label: const Text('Resetear mochilas y órdenes',
                  style: TextStyle(color: Colors.orange)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.orange),
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),
          ],

        // ── Cerrar sesión ─────────────────────────────────────────────
        FilledButton.icon(
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            minimumSize: const Size.fromHeight(48),
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  String _typeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'admin':
        return 'Administrador';
      case 'lider':
        return 'Líder';
      case 'mensajero':
        return 'Mensajero';
      default:
        return type.isEmpty ? 'Usuario' : type;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4, left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
