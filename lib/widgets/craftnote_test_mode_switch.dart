import 'package:flutter/material.dart';
import '../services/craftnote_credentials_service.dart';

/// Interactive Switch & Indicator badge for toggling between Craftnote Test Mode (Sandbox)
/// and Live Production Mode. Usable across Manager and Techniker roles.
class CraftnoteTestModeSwitch extends StatefulWidget {
  final bool compact;
  final ValueChanged<bool>? onChanged;

  const CraftnoteTestModeSwitch({
    super.key,
    this.compact = false,
    this.onChanged,
  });

  @override
  State<CraftnoteTestModeSwitch> createState() => _CraftnoteTestModeSwitchState();
}

class _CraftnoteTestModeSwitchState extends State<CraftnoteTestModeSwitch> {
  @override
  Widget build(BuildContext context) {
    final isTest = CraftnoteCredentialsService.isTestMode;

    if (widget.compact) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isTest ? Colors.blue.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isTest ? Colors.blue.shade300 : Colors.red.shade300,
            width: 1.2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            final next = !isTest;
            setState(() {
              CraftnoteCredentialsService.setTestMode(next);
            });
            widget.onChanged?.call(next);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isTest ? Icons.shield : Icons.warning_amber_rounded,
                size: 16,
                color: isTest ? Colors.blue.shade800 : Colors.red.shade800,
              ),
              const SizedBox(width: 4),
              Text(
                isTest ? 'Test (Sandbox)' : 'Live (Produktiv)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isTest ? Colors.blue.shade900 : Colors.red.shade900,
                ),
              ),
              const SizedBox(width: 2),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: isTest,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: Colors.blue.shade700,
                  activeTrackColor: Colors.blue.shade200,
                  inactiveThumbColor: Colors.red.shade700,
                  inactiveTrackColor: Colors.red.shade200,
                  onChanged: (val) {
                    setState(() {
                      CraftnoteCredentialsService.setTestMode(val);
                    });
                    widget.onChanged?.call(val);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Standard card mode
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isTest ? Colors.blue.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTest ? Colors.blue.shade300 : Colors.red.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isTest ? Icons.shield : Icons.warning_amber_rounded,
            color: isTest ? Colors.blue.shade800 : Colors.red.shade800,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isTest ? 'Test-Modus aktiv (Sandbox)' : 'PRODUKTIV-MODUS AKTIV',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isTest ? Colors.blue.shade900 : Colors.red.shade900,
                  ),
                ),
                Text(
                  isTest
                      ? 'Uploads gehen in Testprojekt #${CraftnoteCredentialsService.testProjectOrderNumber}'
                      : 'ACHTUNG: Uploads gehen direkt in das echte Produktivprojekt!',
                  style: TextStyle(
                    fontSize: 11,
                    color: isTest ? Colors.blue.shade800 : Colors.red.shade800,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isTest,
            activeColor: Colors.blue.shade700,
            inactiveThumbColor: Colors.red.shade700,
            onChanged: (val) {
              setState(() {
                CraftnoteCredentialsService.setTestMode(val);
              });
              widget.onChanged?.call(val);
            },
          ),
        ],
      ),
    );
  }
}

