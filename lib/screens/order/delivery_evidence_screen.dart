import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:signature/signature.dart';
import '../../config/api_config.dart';
import '../../services/api_service.dart';

class DeliveryEvidenceScreen extends StatefulWidget {
  final int orderId;
  final int idUsuario;
  final String folioOrden;

  const DeliveryEvidenceScreen({
    super.key,
    required this.orderId,
    required this.idUsuario,
    required this.folioOrden,
  });

  @override
  State<DeliveryEvidenceScreen> createState() => _DeliveryEvidenceScreenState();
}

class _DeliveryEvidenceScreenState extends State<DeliveryEvidenceScreen> {
  final _nombreCtrl = TextEditingController();
  final _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  String? _fotoBase64;
  bool _saving = false;
  bool _loadingExisting = true;
  bool _saved = false;
  bool _pickingImage = false;

  String _normalizeBase64(String raw) {
    final withoutPrefix = raw.contains(',') ? raw.split(',').last : raw;
    return withoutPrefix.replaceAll(RegExp(r'\s+'), '').trim();
  }

  Uint8List? _safeDecodeBase64Image(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return base64Decode(_normalizeBase64(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final svc = ApiService();
      final data = await svc.get(ApiConfig.orderEvidencia(widget.orderId));
      if (data != null && mounted) {
        final map = Map<String, dynamic>.from(data as Map);
        if (map['nombreReceptor'] != null) {
          _nombreCtrl.text = map['nombreReceptor'] as String;
        }
        if (map['fotoBase64'] != null) {
          setState(() => _fotoBase64 = _normalizeBase64(map['fotoBase64'] as String));
        }
        // La firma existente se muestra como imagen, no se recarga en el pad
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingExisting = false);
  }

  Future<void> _takePicture() async {
    if (_pickingImage) return;
    FocusScope.of(context).unfocus();

    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (cameraStatus.isPermanentlyDenied || cameraStatus.isRestricted) {
        if (mounted) {
          final openSettings = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Permiso de cámara bloqueado'),
              content: const Text(
                'Activa el permiso de cámara en Ajustes para tomar foto. También puedes usar Galería.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Galería'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Abrir Ajustes'),
                ),
              ],
            ),
          );
          if (openSettings == true) {
            await openAppSettings();
          } else {
            await _pickFromGallery();
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permite acceso a la cámara para tomar foto')),
        );
      }
      return;
    }

    final picker = ImagePicker();
    setState(() => _pickingImage = true);
    try {
      XFile? xFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      // Reintento único para error intermitente de AVFoundation en iOS.
      if (xFile == null && Platform.isIOS) {
        await Future.delayed(const Duration(milliseconds: 350));
        xFile = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          maxWidth: 1200,
          maxHeight: 1200,
        );
      }

      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      setState(() => _fotoBase64 = base64Encode(bytes));
    } on PlatformException {
      // iOS puede devolver errores AVFoundation temporales (-11819).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La cámara no está disponible por el momento. Se abrirá galería.'),
          ),
        );
      }
      if (Platform.isIOS) {
        await _pickFromGallery(ignoreLock: true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo tomar la foto. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _pickFromGallery({bool ignoreLock = false}) async {
    if (_pickingImage && !ignoreLock) return;

    final photosStatus = await Permission.photos.request();
    if (!photosStatus.isGranted && !photosStatus.isLimited) {
      if (photosStatus.isPermanentlyDenied || photosStatus.isRestricted) {
        if (mounted) {
          final openSettings = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Permiso de fotos bloqueado'),
              content: const Text(
                'Activa acceso a Fotos en Ajustes para cargar evidencia desde la galería.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Abrir Ajustes'),
                ),
              ],
            ),
          );
          if (openSettings == true) {
            await openAppSettings();
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permite acceso a Fotos para seleccionar imagen')),
        );
      }
      return;
    }

    final picker = ImagePicker();
    if (!ignoreLock) {
      setState(() => _pickingImage = true);
    }
    try {
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1200,
        maxHeight: 1200,
        requestFullMetadata: false,
      );
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      setState(() => _fotoBase64 = base64Encode(bytes));
    } on PlatformException catch (e) {
      if (mounted) {
        final message = e.message ?? '';
        final isSandboxIssue = message.toLowerCase().contains('sandbox') ||
            message.toLowerCase().contains('operation not permitted');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSandboxIssue
                  ? 'iOS bloqueó temporalmente el acceso a galería. Cierra y abre la app e intenta de nuevo.'
                  : 'No se pudo abrir la galería. Intenta nuevamente.',
            ),
          ),
        );
      }
      if (Platform.isIOS) {
        await _pickFromFiles(ignoreLock: true);
      }
    } finally {
      if (mounted && !ignoreLock) setState(() => _pickingImage = false);
    }
  }

  Future<void> _pickFromFiles({bool ignoreLock = false}) async {
    if (_pickingImage && !ignoreLock) return;
    if (!ignoreLock) {
      setState(() => _pickingImage = true);
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo leer la imagen seleccionada')),
          );
        }
        return;
      }

      if (mounted) {
        setState(() => _fotoBase64 = base64Encode(bytes!));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el selector de archivos')),
        );
      }
    } finally {
      if (mounted && !ignoreLock) setState(() => _pickingImage = false);
    }
  }

  Future<void> _save() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el nombre de quien recibe')),
      );
      return;
    }
    if (_fotoBase64 == null && !_signatureController.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos una foto o la firma del receptor')),
      );
      return;
    }

    setState(() => _saving = true);

    String? firmaBase64;
    if (_signatureController.isNotEmpty) {
      final Uint8List? pngBytes = await _signatureController.toPngBytes();
      if (pngBytes != null) {
        firmaBase64 = base64Encode(pngBytes);
      }
    }

    try {
      final svc = ApiService();
      await svc.post(ApiConfig.orderEvidencia(widget.orderId), {
        'idUsuario': widget.idUsuario,
        'nombreReceptor': nombre,
        if (_fotoBase64 != null) 'fotoBase64': _normalizeBase64(_fotoBase64!),
        if (firmaBase64 != null) 'firmaBase64': firmaBase64,
      });
      if (mounted) {
        setState(() => _saved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Evidencia guardada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photoBytes = _safeDecodeBase64Image(_fotoBase64);

    return Scaffold(
      appBar: AppBar(
        title: Text('Evidencia — ${widget.folioOrden}'),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save),
            onPressed: _saving ? null : _save,
            tooltip: 'Guardar evidencia',
          ),
        ],
      ),
      body: _loadingExisting
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Nombre del receptor ───────────────────────────
                  _SectionTitle(title: 'Nombre de quien recibe'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nombreCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Nombre completo del receptor',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Foto del cliente ──────────────────────────────
                  _SectionTitle(title: 'Foto del cliente con paquete'),
                  const SizedBox(height: 8),
                  if (_fotoBase64 != null && photoBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        photoBytes,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  if (_fotoBase64 != null && photoBytes == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Text(
                        'No se pudo mostrar la foto guardada. Puedes retomar la foto para reemplazarla.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.camera_alt),
                          label: Text(_fotoBase64 == null ? 'Tomar foto' : 'Retomar foto'),
                          onPressed: _pickingImage ? null : _takePicture,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galería'),
                        onPressed: _pickingImage ? null : _pickFromGallery,
                      ),
                    ],
                  ),
                  if (_fotoBase64 != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text('Eliminar foto', style: TextStyle(color: Colors.red)),
                        onPressed: () => setState(() => _fotoBase64 = null),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // ── Firma del receptor ────────────────────────────
                  _SectionTitle(title: 'Firma del receptor'),
                  const SizedBox(height: 8),
                  Text(
                    'El receptor debe firmar con el dedo en el área de abajo',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Signature(
                        controller: _signatureController,
                        height: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Borrar firma'),
                      onPressed: () => _signatureController.clear(),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Guardar ───────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: const Text('Guardar evidencia de entrega'),
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue),
    );
  }
}
