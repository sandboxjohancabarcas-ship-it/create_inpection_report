import 'package:flutter/material.dart';
import 'package:wartungstool/models/door.dart';
import 'package:wartungstool/models/door_conflict.dart';
import 'package:wartungstool/services/database_service.dart';
import '../models/models.dart';
import '../widgets/master_portal_home_button.dart';

class DoorConflictReviewPage extends StatefulWidget {
  final List<DoorConflict> conflicts;

  const DoorConflictReviewPage({
    super.key,
    required this.conflicts,
  });

  @override
  _DoorConflictReviewPageState createState() => _DoorConflictReviewPageState();
}

class _DoorConflictReviewPageState extends State<DoorConflictReviewPage> {
  // We group conflicts by doorAlias (or doorNumber if alias is empty)
  // to present one cohesive card per door rather than one card per field.
  late Map<String, List<DoorConflict>> _groupedConflicts;
  late List<String> _doorKeys;

  // Track resolutions at the door level
  final Map<String, DoorResolutionAction> _doorActions = {};
  // For keepBoth action, track the new alias
  final Map<String, TextEditingController> _newAliasControllers = {};

  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _groupAndInitialize();
  }

  void _groupAndInitialize() {
    _groupedConflicts = {};
    for (final conflict in widget.conflicts) {
      final door = conflict.incomingDoor;
      final key = door.doorAlias?.isNotEmpty == true
          ? door.doorAlias!
          : 'NO-ALIAS-${door.doorNumber}-${door.floor}';

      if (!_groupedConflicts.containsKey(key)) {
        _groupedConflicts[key] = [];
      }
      _groupedConflicts[key]!.add(conflict);
    }

    _doorKeys = _groupedConflicts.keys.toList();

    for (final key in _doorKeys) {
      final doorConflicts = _groupedConflicts[key]!;
      // Default to keepExisting
      _doorActions[key] = DoorResolutionAction.keepExisting;

      final incomingDoor = doorConflicts.first.incomingDoor;
      final defaultNewAlias = '${incomingDoor.doorAlias ?? incomingDoor.doorNumber}_NEU';
      _newAliasControllers[key] = TextEditingController(text: defaultNewAlias);
    }
  }

  @override
  void dispose() {
    for (final controller in _newAliasControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int totalSafetyConflicts = widget.conflicts.where((c) => c.type == DoorConflictType.safetyFlagChange).length;
    int totalIdentityConflicts = widget.conflicts.where((c) => c.type == DoorConflictType.identityCollision).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Türdatenkonflikte lösen (${_doorKeys.length} Türen)'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: const [
          MasterPortalHomeButton(color: Colors.white),
        ],
      ),
      body: Column(
        children: [
          // Informational Alert Banner
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Konflikte bei ${_doorKeys.length} Türen festgestellt',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Es gibt $totalIdentityConflicts Identitätskonflikte (rot) und $totalSafetyConflicts sicherheitsrelevante Abweichungen (orange). '
                        'Bitte legen Sie für jede Tür fest, wie verfahren werden soll.',
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bulk Actions Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _setAllActions(DoorResolutionAction.keepExisting),
                  icon: const Icon(Icons.history),
                  label: const Text('Alle: Bestehend behalten'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _setAllActions(DoorResolutionAction.acceptIncoming),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Alle: Importieren'),
                ),
              ],
            ),
          ),

          // Conflicts List
          Expanded(
            child: ListView.builder(
              itemCount: _doorKeys.length,
              itemBuilder: (context, index) {
                final key = _doorKeys[index];
                final doorConflicts = _groupedConflicts[key]!;
                return _buildDoorConflictCard(key, doorConflicts);
              },
            ),
          ),

          // Bottom Navigation bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isApplying ? null : _applyResolutions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isApplying
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Wende Entscheidungen an...'),
                            ],
                          )
                        : const Text('Entscheidungen anwenden'),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  ),
                  child: const Text('Abbrechen'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _setAllActions(DoorResolutionAction action) {
    setState(() {
      for (final key in _doorKeys) {
        // Identity collisions cannot be cleanly replaced or just accepted without new alias;
        // keepExisting is always allowed. If bulk-setting to acceptIncoming, skip identity collisions.
        final hasIdentity = _groupedConflicts[key]!.any((c) => c.type == DoorConflictType.identityCollision);
        if (hasIdentity && action == DoorResolutionAction.acceptIncoming) {
          _doorActions[key] = DoorResolutionAction.keepBoth;
        } else {
          _doorActions[key] = action;
        }
      }
    });
  }

  Widget _buildDoorConflictCard(String key, List<DoorConflict> doorConflicts) {
    final firstConflict = doorConflicts.first;
    final incomingDoor = firstConflict.incomingDoor;
    final existingDoor = firstConflict.existingDoor;
    final hasIdentity = doorConflicts.any((c) => c.type == DoorConflictType.identityCollision);
    final hasSafety = doorConflicts.any((c) => c.type == DoorConflictType.safetyFlagChange);
    final hasLogical = doorConflicts.any((c) => c.type == DoorConflictType.logicalViolation);

    Color cardBorderColor = Colors.grey.shade300;
    Color headerBgColor = Colors.grey.shade100;
    IconData headerIcon = Icons.door_front_door;
    Color headerIconColor = Colors.blueGrey;

    if (hasIdentity) {
      cardBorderColor = Colors.red.shade300;
      headerBgColor = Colors.red.shade50;
      headerIcon = Icons.error_outline;
      headerIconColor = Colors.red;
    } else if (hasSafety) {
      cardBorderColor = Colors.orange.shade300;
      headerBgColor = Colors.orange.shade50;
      headerIcon = Icons.gavel_rounded;
      headerIconColor = Colors.orange.shade800;
    } else if (hasLogical) {
      cardBorderColor = Colors.purple.shade300;
      headerBgColor = Colors.purple.shade50;
      headerIcon = Icons.rule_folder_rounded;
      headerIconColor = Colors.purple;
    }

    final action = _doorActions[key]!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cardBorderColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header banner for the door card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: headerBgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                Icon(headerIcon, color: headerIconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tür: ${incomingDoor.doorAlias ?? incomingDoor.doorNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Nummer: ${incomingDoor.doorNumber} | Geschoss: ${incomingDoor.floor} | Raum: ${incomingDoor.roomNumber} (${incomingDoor.roomDesignation})',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Detail differences or logical issues list
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Festgestellte Abweichungen / Konflikte:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                ),
                const SizedBox(height: 8),

                ...doorConflicts.map((conflict) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: conflict.type.isBlocking
                                    ? Colors.red
                                    : conflict.type.isSafety
                                        ? Colors.orange
                                        : Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${conflict.type.label} (${conflict.ruleCode}): ${conflict.fieldLabel}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                conflict.message,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                              ),
                              if (conflict.type != DoorConflictType.logicalViolation) ...[
                                const SizedBox(height: 4),
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 12, color: Colors.black),
                                    children: [
                                      const TextSpan(text: 'Bestehend (DB): ', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                      TextSpan(text: '"${conflict.existingValue}"'),
                                      const TextSpan(text: '  ➔  '),
                                      const TextSpan(text: 'Import: ', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                      TextSpan(text: '"${conflict.incomingValue}"'),
                                    ],
                                  ),
                                ),
                              ],
                              if (conflict.compliance != null) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.orange.shade200),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline, color: Colors.orange.shade800, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
                                            children: [
                                              TextSpan(
                                                text: '[${conflict.compliance!.norm}]: ',
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                              TextSpan(text: conflict.compliance!.riskNote),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const Divider(height: 24),

                // Decision/Resolution radio buttons
                const Text(
                  'Entscheidung für diese Tür:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),

                RadioListTile<DoorResolutionAction>(
                  dense: true,
                  title: const Text('Bestehende Daten behalten'),
                  subtitle: const Text('Importierte Daten verwerfen'),
                  value: DoorResolutionAction.keepExisting,
                  groupValue: action,
                  onChanged: (val) {
                    setState(() {
                      _doorActions[key] = val!;
                    });
                  },
                ),

                if (!hasLogical) ...[
                  RadioListTile<DoorResolutionAction>(
                    dense: true,
                    title: const Text('Importierte Daten übernehmen'),
                    subtitle: const Text('Überschreibt die bestehenden Stammdaten'),
                    value: DoorResolutionAction.acceptIncoming,
                    groupValue: action,
                    onChanged: (val) {
                      setState(() {
                        _doorActions[key] = val!;
                      });
                    },
                  ),
                ],

                if (hasIdentity) ...[
                  RadioListTile<DoorResolutionAction>(
                    dense: true,
                    title: const Text('Beide behalten (Importierte Tür umbenennen)'),
                    subtitle: const Text('Speichert die Tür unter einem neuen Alias'),
                    value: DoorResolutionAction.keepBoth,
                    groupValue: action,
                    onChanged: (val) {
                      setState(() {
                        _doorActions[key] = val!;
                      });
                    },
                  ),
                  if (action == DoorResolutionAction.keepBoth)
                    Padding(
                      padding: const EdgeInsets.only(left: 32, right: 16, bottom: 8),
                      child: TextField(
                        controller: _newAliasControllers[key],
                        decoration: const InputDecoration(
                          labelText: 'Neuer Tür-Alias (max 24 Zeichen)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLength: 24,
                      ),
                    ),
                ],

                RadioListTile<DoorResolutionAction>(
                  dense: true,
                  title: const Text('Import überspringen'),
                  subtitle: const Text('Keine Aktion für diese Tür ausführen'),
                  value: DoorResolutionAction.skip,
                  groupValue: action,
                  onChanged: (val) {
                    setState(() {
                      _doorActions[key] = val!;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _applyResolutions() async {
    // Validate custom aliases for keepBoth decisions
    for (final key in _doorKeys) {
      if (_doorActions[key] == DoorResolutionAction.keepBoth) {
        final val = _newAliasControllers[key]!.text.trim();
        if (val.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bitte geben Sie einen neuen Alias für die Tür ${_groupedConflicts[key]!.first.incomingDoor.doorAlias ?? key} ein.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    // Check if there are safety-relevant changes accepted
    bool hasAcceptedSafetyChanges = false;
    for (final key in _doorKeys) {
      if (_doorActions[key] == DoorResolutionAction.acceptIncoming) {
        final conflicts = _groupedConflicts[key]!;
        if (conflicts.any((c) => c.type == DoorConflictType.safetyFlagChange)) {
          hasAcceptedSafetyChanges = true;
          break;
        }
      }
    }

    if (hasAcceptedSafetyChanges) {
      final confirm = await _showSafetyConfirmationDialog();
      if (confirm != true) return;
    }

    setState(() {
      _isApplying = true;
    });

    try {
      // Build final decision list by mapping decisions back to the flat conflicts list
      final flatConflicts = <DoorConflict>[];

      for (final key in _doorKeys) {
        final action = _doorActions[key]!;
        final newAlias = _newAliasControllers[key]?.text.trim();
        final conflicts = _groupedConflicts[key]!;

        for (final conflict in conflicts) {
          conflict.resolution = action;
          conflict.newAlias = newAlias;
          flatConflicts.add(conflict);
        }
      }

      await DatabaseService.applyDoorConflictResolutions(flatConflicts);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Türdaten-Konflikte erfolgreich gelöst.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Auflösen der Konflikte: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  Future<bool?> _showSafetyConfirmationDialog() async {
    final textController = TextEditingController();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Sicherheitsfreigabe erforderlich'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sie haben sich entschieden, überschreibende Daten für sicherheitsrelevante '
                'Türfunktionen (z. B. Fluchtwegsteuerung, Panikfunktion, DIN-Anschlag) zu übernehmen. '
                'Dies kann rechtliche Haftungsfolgen nach sich ziehen, falls die physikalischen Türen vor Ort nicht übereinstimmen.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'Bitte bestätigen Sie diese Freigabe, indem Sie "BESTÄTIGEN" in Großbuchstaben eingeben:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  hintText: 'BESTÄTIGEN',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                if (textController.text.trim() == 'BESTÄTIGEN') {
                  Navigator.pop(context, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Bitte geben Sie das Wort "BESTÄTIGEN" exakt ein.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
              child: const Text('Freigeben & Fortfahren'),
            ),
          ],
        );
      },
    );
  }
}
