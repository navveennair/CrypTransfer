import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../widgets/shared_widgets.dart';

class SecurityPulseFeed extends StatelessWidget {
  final _adminRepo = AdminRepository();

  SecurityPulseFeed({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot>(
      stream: _adminRepo.streamSecurityAuditLog(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final logs = snapshot.data!.docs;
        
        if (logs.isEmpty) {
          return Center(
            child: Text('No security events detected', style: TextStyle(color: cs.onSurfaceVariant)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: logs.length,
          itemBuilder: (context, i) {
            final data = logs[i].data() as Map<String, dynamic>;
            final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
            final event = data['event'] as String? ?? 'UNKNOWN_EVENT';
            
            return _SecurityLogTile(
              event: event,
              details: data['details'] as String? ?? '',
              timestamp: timestamp,
            );
          },
        );
      },
    );
  }
}

class _SecurityLogTile extends StatelessWidget {
  final String event;
  final String details;
  final DateTime timestamp;

  const _SecurityLogTile({
    required this.event,
    required this.details,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCritical = event.contains('ERROR') || event.contains('FAILURE') || event.contains('WIPE');
    final color = isCritical ? cs.error : cs.primary;

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      borderColor: isCritical ? cs.error.withValues(alpha: 0.5) : cs.outline,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCritical ? Icons.warning_amber_rounded : Icons.shield_outlined,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      event.toUpperCase(),
                      style: GoogleFonts.orbitron(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      DateFormat('HH:mm:ss').format(timestamp),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  style: GoogleFonts.inter(
                    color: cs.onSurface,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
