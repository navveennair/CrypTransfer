import 'package:flutter/material.dart';

import '../../data/models/stale_key_scan_result.dart';
import '../../data/repositories/key_repository.dart';
import '../widgets/shared_widgets.dart';

/// Scan → confirm → clear flow for leftover RSA/AES key material.
/// Show via showModalBottomSheet — kept as its own StatefulWidget (not
/// folded into SidebarDrawer, which stays a plain StatelessWidget) because
/// this flow has real async state: scanning, confirming, clearing.
class ClearCacheSheet extends StatefulWidget {
  const ClearCacheSheet({super.key});

  @override
  State<ClearCacheSheet> createState() => _ClearCacheSheetState();
}

enum _Phase { scanning, clean, found, clearing }

class _ClearCacheSheetState extends State<ClearCacheSheet> {
  final _keyRepo = KeyRepository();
  _Phase _phase = _Phase.scanning;
  StaleKeyScanResult? _scan;
  String? _scanError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runScan());
  }

  Future<void> _runScan() async {
    try {
      final scan = await _keyRepo.scanForStaleKeys();
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _phase = scan.isClean ? _Phase.clean : _Phase.found;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanError = e.toString());
    }
  }

  String _summaryMessage(StaleKeyScanResult scan) {
    final parts = <String>[];
    if (scan.hasStaleRsaSession) {
      parts.add('1 stale RSA session');
    }
    final n = scan.staleTransferIds.length;
    if (n > 0) {
      parts.add('$n stale transfer${n == 1 ? '' : 's'} with leftover AES '
          'key${n == 1 ? '' : 's'}');
    }
    return 'Found ${parts.join(' and ')}.';
  }

  Future<void> _onClear() async {
    final scan = _scan;
    if (scan == null) return;
    setState(() => _phase = _Phase.clearing);
    try {
      await _keyRepo.clearStaleKeys(scan);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_summaryMessage(scan).replaceFirst('Found', 'Cleared')),
          backgroundColor: Theme.of(context).colorScheme.secondary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomSheetHandle(),
          const SizedBox(height: 16),
          ..._buildPhaseContent(cs, tt),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 8),
        ],
      ),
    );
  }

  List<Widget> _buildPhaseContent(ColorScheme cs, TextTheme tt) {
    if (_scanError != null) {
      return [
        Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
        const SizedBox(height: 16),
        Text('Scan Failed', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(
          _scanError!.replaceFirst('Exception: ', ''),
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        CrypButton(
          label: const Text('Dismiss'),
          onPressed: () => Navigator.pop(context),
          color: cs.onSurfaceVariant,
          height: 44,
        ),
      ];
    }

    switch (_phase) {
      case _Phase.scanning:
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ),
        ];

      case _Phase.clean:
        return [
          Icon(Icons.verified_rounded, size: 48, color: cs.secondary),
          const SizedBox(height: 16),
          Text('Already Clean', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            'No stale keys found.',
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          CrypButton(
            label: const Text('Dismiss'),
            onPressed: () => Navigator.pop(context),
            color: cs.primary,
            height: 44,
          ),
        ];

      case _Phase.found:
        final scan = _scan!;
        return [
          Icon(Icons.warning_amber_rounded, size: 48, color: cs.tertiary),
          const SizedBox(height: 16),
          Text('Stale Keys Found', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            _summaryMessage(scan),
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: CrypButton(
                  label: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                  color: cs.onSurfaceVariant,
                  height: 44,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CrypButton(
                  label: const Text('Clear'),
                  onPressed: _onClear,
                  color: cs.error,
                  height: 44,
                ),
              ),
            ],
          ),
        ];

      case _Phase.clearing:
        return [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(),
          ),
          const SizedBox(height: 16),
          Text('Clearing stale keys…', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ];
    }
  }
}
