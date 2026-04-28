import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
    setState(() {
      _uiSoundEnabled = _prefs!.getBool('uiSoundEnabled') ?? true;
      _uiVolume = _prefs!.getDouble('uiVolume') ?? 0.7;
      _codebarSoundEnabled = _prefs!.getBool('codebarSoundEnabled') ?? true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(title: 'Sonidos de interfaz'),
        SwitchListTile(
          title: const Text('Sonidos de UI'),
          subtitle: const Text('Activar sonidos al interactuar con la app'),
          value: _uiSoundEnabled,
          onChanged: (v) {
            setState(() => _uiSoundEnabled = v);
            _prefs?.setBool('uiSoundEnabled', v);
          },
        ),
        if (_uiSoundEnabled) ...[
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
        const Divider(),
        const _SectionHeader(title: 'Escáner de códigos'),
        SwitchListTile(
          title: const Text('Sonido del escáner'),
          subtitle: const Text('Reproducir sonido al escanear un código'),
          value: _codebarSoundEnabled,
          onChanged: (v) {
            setState(() => _codebarSoundEnabled = v);
            _prefs?.setBool('codebarSoundEnabled', v);
          },
        ),
        const Divider(),
        const _SectionHeader(title: 'Acerca de'),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Versión'),
          trailing: Text('1.0.0', style: TextStyle(color: Colors.grey)),
        ),
        const ListTile(
          leading: Icon(Icons.business),
          title: Text('Desarrollado por'),
          trailing: Text('Quantum Nest', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
