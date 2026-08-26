import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerDialog extends StatefulWidget {
  final String title;

  const BarcodeScannerDialog({
    super.key,
    this.title = 'Barcode / QR-Code scannen',
  });

  /// Shows the barcode scanner modal dialog and returns the scanned code string or null.
  static Future<String?> show(BuildContext context, {String title = 'Barcode / QR-Code scannen'}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => BarcodeScannerDialog(title: title),
    );
  }

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  final TextEditingController _manualController = TextEditingController();
  bool _isScanned = false;
  bool _isMobilePlatform = false;

  @override
  void initState() {
    super.initState();
    _isMobilePlatform = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  }

  @override
  void dispose() {
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue?.trim();
      if (rawValue != null && rawValue.isNotEmpty) {
        _isScanned = true;
        Navigator.pop(context, rawValue);
        break;
      }
    }
  }

  void _submitManualInput() {
    final text = _manualController.text.trim();
    if (text.isNotEmpty) {
      Navigator.pop(context, text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.qr_code_scanner, color: Colors.deepPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isMobilePlatform) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        MobileScanner(
                          controller: _controller,
                          onDetect: _onDetect,
                          errorBuilder: (context, error, child) {
                            return Container(
                              color: Colors.black87,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Kamera-Fehler (${error.errorCode}):\n${error.errorDetails?.message ?? "Kamera konnte nicht gestartet werden. Bitte Berechtigungen prüfen."}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: ValueListenableBuilder(
                        valueListenable: _controller,
                        builder: (context, state, child) {
                          return Icon(
                            state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                            color: state.torchState == TorchState.on ? Colors.amber : Colors.grey,
                          );
                        },
                      ),
                      onPressed: () => _controller.toggleTorch(),
                      tooltip: 'Blitzlicht umschalten',
                    ),
                    IconButton(
                      icon: const Icon(Icons.cameraswitch, color: Colors.blue),
                      onPressed: () => _controller.switchCamera(),
                      tooltip: 'Kamera wechseln',
                    ),
                  ],
                ),
                const Divider(),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Kamerascan ist auf Android/iOS verfügbar. Bitte Barcode manuell eingeben:',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _manualController,
                decoration: InputDecoration(
                  labelText: 'Barcode / Alias manuell eingeben',
                  hintText: 'z.B. BAR-2026-9941',
                  prefixIcon: const Icon(Icons.keyboard),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: _submitManualInput,
                  ),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitManualInput(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton.icon(
          onPressed: _submitManualInput,
          icon: const Icon(Icons.check),
          label: const Text('Übernehmen'),
        ),
      ],
    );
  }
}
