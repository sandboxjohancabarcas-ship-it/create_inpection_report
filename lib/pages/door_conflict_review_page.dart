import 'package:flutter/material.dart';
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
  // Group conflicts by doorAlias (or doorNumber if alias is empty)
  late Map<String, List<DoorConflict>> _groupedConflicts;
  late List<String> _doorKeys;

  // Track actions at the door level (e.g. keepBoth for identity collisions or skip)
  final Map<String, DoorResolutionAction?> _doorLevelActions = {};
  final Map<String, TextEditingController> _newAliasControllers = {};

  // Track resolutions and custom inputs per individual property conflict
  final Map<DoorConflict, DoorResolutionAction> _fieldActions = {};
  final Map<DoorConflict, TextEditingController> _fieldCustomControllers = {};

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
      final firstDoor = doorConflicts.first.incomingDoor;

      _doorLevelActions[key] = null;
      final defaultNewAlias = '${firstDoor.doorAlias ?? firstDoor.doorNumber}_NEU';
      _newAliasControllers[key] = TextEditingController(text: defaultNewAlias);

      for (final conflict in doorConflicts) {
        // Default to addToMasterOptions if new dropdown option introduced, else keepExisting
        _fieldActions[conflict] = (conflict.type == DoorConflictType.newDropdownOption)
            ? DoorResolutionAction.addToMasterOptions
            : DoorResolutionAction.keepExisting;

        final initialText = conflict.incomingValue.isNotEmpty && conflict.incomingValue != '(leer)'
            ? conflict.incomingValue
            : conflict.existingValue;
        _fieldCustomControllers[conflict] = TextEditingController(text: initialText);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _newAliasControllers.values) {
      controller.dispose();
    }
    for (final controller in _fieldCustomControllers.values) {
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
                        'Sie können für jede Tür und jede Eigenschaft einzeln festlegen, welcher Wert übernommen wird.',
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
                  label: const Text('Alle Felder: Bestehend behalten'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _setAllActions(DoorResolutionAction.acceptIncoming),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Alle Felder: Importieren'),
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
        _doorLevelActions[key] = null;
        for (final conflict in _groupedConflicts[key]!) {
          if (conflict.type == DoorConflictType.identityCollision) {
            _doorLevelActions[key] = DoorResolutionAction.keepBoth;
          } else {
            _fieldActions[conflict] = action;
          }
        }
      }
    });
  }

  Widget _buildDoorConflictCard(String key, List<DoorConflict> doorConflicts) {
    final firstConflict = doorConflicts.first;
    final incomingDoor = firstConflict.incomingDoor;

    // Deduplicate conflicts per field name
    final Map<String, DoorConflict> uniqueConflictsMap = {};
    for (final conflict in doorConflicts) {
      final conflictKey = '${conflict.fieldName}_${conflict.ruleCode}';
      if (!uniqueConflictsMap.containsKey(conflictKey)) {
        uniqueConflictsMap[conflictKey] = conflict;
      }
    }
    final uniqueConflicts = uniqueConflictsMap.values.toList();

    final hasIdentity = uniqueConflicts.any((c) => c.type == DoorConflictType.identityCollision);
    final hasSafety = uniqueConflicts.any((c) => c.type == DoorConflictType.safetyFlagChange);
    final hasLogical = uniqueConflicts.any((c) => c.type == DoorConflictType.logicalViolation);
    final hasDropdownOption = uniqueConflicts.any((c) => c.type == DoorConflictType.newDropdownOption);

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
    } else if (hasDropdownOption) {
      cardBorderColor = Colors.blue.shade300;
      headerBgColor = Colors.blue.shade50;
      headerIcon = Icons.playlist_add_check_rounded;
      headerIconColor = Colors.blue.shade800;
    }

    final doorLevelAction = _doorLevelActions[key];

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
                      if (firstConflict.sourceContext != null && firstConflict.sourceContext!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Herkunft: ${firstConflict.sourceContext}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade800),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Identity collision option header (if applicable)
                if (hasIdentity) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Identitätskonflikt (Gleicher Alias für verschiedene Türen):',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        RadioListTile<DoorResolutionAction>(
                          dense: true,
                          title: const Text('Beide behalten (Importierte Tür unter neuem Alias speichern)'),
                          value: DoorResolutionAction.keepBoth,
                          groupValue: doorLevelAction ?? DoorResolutionAction.keepBoth,
                          onChanged: (val) {
                            setState(() {
                              _doorLevelActions[key] = val;
                            });
                          },
                        ),
                        if (doorLevelAction == null || doorLevelAction == DoorResolutionAction.keepBoth)
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
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Individual Per-Property Conflicts List
                const Text(
                  'Festgestellte Abweichungen (Einzelauswahl pro Eigenschaft):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                ),
                const SizedBox(height: 10),

                ...uniqueConflicts.map((conflict) {
                  final fieldAction = _fieldActions[conflict] ?? DoorResolutionAction.keepExisting;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Property Header & Severity Indicator
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
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
                              '${conflict.fieldLabel} (${conflict.ruleCode})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),

                        if (conflict.type != DoorConflictType.logicalViolation) ...[
                          const SizedBox(height: 6),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 12, color: Colors.black),
                              children: [
                                const TextSpan(text: 'DB: ', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                TextSpan(text: '"${conflict.existingValue}"'),
                                const TextSpan(text: '  ➔  '),
                                const TextSpan(text: 'Import: ', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                TextSpan(text: '"${conflict.incomingValue}"'),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 4),

                        // Property Individual Decision Options
                        RadioListTile<DoorResolutionAction>(
                          dense: true,
                          title: Text('Bestehenden Wert behalten ("${conflict.existingValue.isEmpty ? '(leer)' : conflict.existingValue}")'),
                          value: DoorResolutionAction.keepExisting,
                          groupValue: fieldAction,
                          onChanged: (val) {
                            setState(() {
                              _fieldActions[conflict] = val!;
                            });
                          },
                        ),

                        if (conflict.type != DoorConflictType.logicalViolation) ...[
                          RadioListTile<DoorResolutionAction>(
                            dense: true,
                            title: Text('Importierten Wert übernehmen ("${conflict.incomingValue.isEmpty ? '(leer)' : conflict.incomingValue}")'),
                            value: DoorResolutionAction.acceptIncoming,
                            groupValue: fieldAction,
                            onChanged: (val) {
                              setState(() {
                                _fieldActions[conflict] = val!;
                              });
                            },
                          ),
                        ],

                        if (conflict.type == DoorConflictType.newDropdownOption) ...[
                          RadioListTile<DoorResolutionAction>(
                            dense: true,
                            title: Text('In Stamm-Menü aufnehmen & für Tür übernehmen ("${conflict.incomingValue}")'),
                            value: DoorResolutionAction.addToMasterOptions,
                            groupValue: fieldAction,
                            onChanged: (val) {
                              setState(() {
                                _fieldActions[conflict] = val!;
                              });
                            },
                          ),
                        ],

                        if (conflict.type != DoorConflictType.logicalViolation) ...[
                          RadioListTile<DoorResolutionAction>(
                            dense: true,
                            title: const Text('Benutzerdefinierter Wert (Freitext)'),
                            value: DoorResolutionAction.customInput,
                            groupValue: fieldAction,
                            onChanged: (val) {
                              setState(() {
                                _fieldActions[conflict] = val!;
                              });
                            },
                          ),
                          if (fieldAction == DoorResolutionAction.customInput)
                            Padding(
                              padding: const EdgeInsets.only(left: 32, right: 16, top: 4, bottom: 8),
                              child: TextField(
                                controller: _fieldCustomControllers[conflict],
                                decoration: InputDecoration(
                                  labelText: 'Eigener Wert für "${conflict.fieldLabel}"',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  );
                }),

                const Divider(height: 24),

                // Entire Door Skip Action
                RadioListTile<DoorResolutionAction>(
                  dense: true,
                  title: const Text('Import dieser Tür komplett überspringen'),
                  subtitle: const Text('Keine Datenänderungen für diese Tür vornehmen'),
                  value: DoorResolutionAction.skip,
                  groupValue: doorLevelAction,
                  onChanged: (val) {
                    setState(() {
                      _doorLevelActions[key] = val;
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
    // Validate custom aliases & custom input text
    for (final key in _doorKeys) {
      if (_doorLevelActions[key] == DoorResolutionAction.keepBoth) {
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
    for (final conflict in widget.conflicts) {
      final doorKey = conflict.incomingDoor.doorAlias?.isNotEmpty == true
          ? conflict.incomingDoor.doorAlias!
          : 'NO-ALIAS-${conflict.incomingDoor.doorNumber}-${conflict.incomingDoor.floor}';

      if (_doorLevelActions[doorKey] == DoorResolutionAction.skip) continue;

      final action = _fieldActions[conflict] ?? DoorResolutionAction.keepExisting;
      if (action == DoorResolutionAction.acceptIncoming || action == DoorResolutionAction.customInput) {
        if (conflict.type == DoorConflictType.safetyFlagChange) {
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
      final flatConflicts = <DoorConflict>[];

      for (final key in _doorKeys) {
        final doorConflicts = _groupedConflicts[key]!;
        final doorLevelAction = _doorLevelActions[key];
        final newAlias = _newAliasControllers[key]?.text.trim();

        for (final conflict in doorConflicts) {
          if (doorLevelAction == DoorResolutionAction.skip) {
            conflict.resolution = DoorResolutionAction.skip;
          } else if (doorLevelAction == DoorResolutionAction.keepBoth && conflict.type == DoorConflictType.identityCollision) {
            conflict.resolution = DoorResolutionAction.keepBoth;
            conflict.newAlias = newAlias;
          } else {
            final fieldAction = _fieldActions[conflict] ?? DoorResolutionAction.keepExisting;
            conflict.resolution = fieldAction;
            if (fieldAction == DoorResolutionAction.customInput) {
              conflict.customValue = _fieldCustomControllers[conflict]?.text.trim();
            }
            if (fieldAction == DoorResolutionAction.keepBoth) {
              conflict.newAlias = newAlias;
            }
          }
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
