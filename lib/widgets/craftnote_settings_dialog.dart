import 'package:flutter/material.dart';
import 'package:wartungstool/services/craftnote_api_service.dart';
import 'package:wartungstool/services/craftnote_credentials_service.dart';

/// Modal dialog allowing users and managers to view and edit Craftnote API credentials,
/// test cloud connectivity, and toggle the mock development adapter.
class CraftnoteSettingsDialog extends StatefulWidget {
  const CraftnoteSettingsDialog({super.key});

  static Future<bool?> show(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => const CraftnoteSettingsDialog(),
    );
  }

  @override
  State<CraftnoteSettingsDialog> createState() =>
      _CraftnoteSettingsDialogState();
}

class _CraftnoteSettingsDialogState extends State<CraftnoteSettingsDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _apiKeyController;
  late TextEditingController _clientIdController;
  late TextEditingController _baseUrlController;
  late TextEditingController _folderController;

  bool _isMockMode = false;
  bool _isTestMode = false;
  bool _obscureApiKey = true;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testStatusMessage;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController =
        TextEditingController(text: CraftnoteCredentialsService.apiKey);
    _clientIdController =
        TextEditingController(text: CraftnoteCredentialsService.clientId);
    _baseUrlController =
        TextEditingController(text: CraftnoteCredentialsService.baseUrl);
    _folderController =
        TextEditingController(text: CraftnoteCredentialsService.folder);
    _isMockMode = CraftnoteCredentialsService.isMockMode;
    _isTestMode = CraftnoteCredentialsService.isTestMode;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _clientIdController.dispose();
    _baseUrlController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testStatusMessage = null;
    });

    try {
      final tempService = CraftnoteApiService(
        apiKey: _apiKeyController.text.trim(),
        clientId: _clientIdController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
      );

      final member = await tempService.getMe();
      setState(() {
        _testSuccess = true;
        _testStatusMessage =
            'Verbindung erfolgreich!\nAngemeldet als: ${member.displayName} (${member.email})';
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testStatusMessage = 'Verbindungstest fehlgeschlagen:\n$e';
      });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await CraftnoteCredentialsService.saveCredentials(
        apiKey: _apiKeyController.text.trim(),
        clientId: _clientIdController.text.trim(),
        folder: _folderController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        mockMode: _isMockMode,
        isTestMode: _isTestMode,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Craftnote-Einstellungen erfolgreich gespeichert.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlaceholder = !CraftnoteCredentialsService.isConfigured;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.cloud_sync, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Craftnote API & Cloud-Einstellungen')),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPlaceholder)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.amber.shade800, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aktuell sind Platzhalter-Zugangsdaten aktiv. Sobald Gottsberg die echten API-Schlüssel bereitstellt, können diese hier ohne Code-Anpassung hinterlegt werden.',
                            style: TextStyle(
                                fontSize: 13, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Mock Mode Switch
                Card(
                  elevation: 0,
                  color:
                      _isMockMode ? Colors.blue.shade50 : Colors.grey.shade100,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: _isMockMode
                          ? Colors.blue.shade300
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: SwitchListTile(
                    title: const Text('Mock-Adapter aktivieren (Offline-Demo)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text(
                      'Simuliert Antworten der Craftnote API (Projekte, Dokumente & Uploads) ohne Netzwerkzugriff.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _isMockMode,
                    activeThumbColor: Colors.blue.shade700,
                    onChanged: (val) {
                      setState(() => _isMockMode = val);
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // API Key
                TextFormField(
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  decoration: InputDecoration(
                    labelText: 'API-Key (X-CN-API-KEY)',
                    hintText: 'CRAFTNOTE_API_KEY_...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscureApiKey = !_obscureApiKey);
                      },
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Bitte geben Sie einen API-Key ein.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Client ID
                TextFormField(
                  controller: _clientIdController,
                  decoration: const InputDecoration(
                    labelText: 'Client-ID (X-CN-CLIENT-ID, optional)',
                    hintText: 'CRAFTNOTE_CLIENT_ID_...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Base URL
                TextFormField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Craftnote API Base-URL',
                    hintText: 'https://api.craftnote.de/v1',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Bitte geben Sie die API Base-URL ein.';
                    }
                    if (!val.startsWith('http://') &&
                        !val.startsWith('https://')) {
                      return 'URL muss mit http:// oder https:// beginnen.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Target Folder
                TextFormField(
                  controller: _folderController,
                  decoration: const InputDecoration(
                    labelText: 'Standard-Zielordner in Craftnote',
                    hintText: 'Wartungslisten',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // Test Environment Mode Safety Switch
                Material(
                  color: _isTestMode ? Colors.blue.shade50 : Colors.red.shade50,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: _isTestMode
                            ? Colors.blue.shade300
                            : Colors.red.shade300),
                  ),
                  child: SwitchListTile(
                    title: Text(
                      _isTestMode
                          ? 'Test-Modus (Sandbox-Schutz aktiv)'
                          : 'Produktiv-Modus (Live-Upload)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _isTestMode
                              ? Colors.blue.shade900
                              : Colors.red.shade900),
                    ),
                    subtitle: Text(
                      _isTestMode
                          ? 'Schreibzugriffe (POST) werden sicher auf das Sandbox-Testprojekt 26-00251-AN umgeleitet, um Produktivdaten zu schützen.'
                          : 'ACHTUNG: Dateien und Fotos werden direkt in die echten Produktivprojekte hochgeladen!',
                      style: TextStyle(
                          fontSize: 11,
                          color: _isTestMode
                              ? Colors.blue.shade800
                              : Colors.red.shade800),
                    ),
                    value: _isTestMode,
                    activeThumbColor: Colors.blue.shade700,
                    onChanged: (val) => setState(() => _isTestMode = val),
                  ),
                ),
                const SizedBox(height: 16),

                // Connection Test Feedback Banner
                if (_testStatusMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _testSuccess
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _testSuccess
                            ? Colors.green.shade400
                            : Colors.red.shade400,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _testSuccess
                              ? Icons.check_circle
                              : Icons.error_outline,
                          color: _testSuccess
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _testStatusMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: _testSuccess
                                  ? Colors.green.shade900
                                  : Colors.red.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Test Connection Button
                OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: Text(_isTesting
                      ? 'Verbindung wird geprüft...'
                      : 'Verbindung testen'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveSettings,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save),
          label: const Text('Speichern'),
        ),
      ],
    );
  }
}
