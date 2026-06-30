import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/admin_repository.dart';

// Palette — must stay in sync with admin_dashboard.dart
const _spfCard    = Color(0xFF111B28);
const _spfBorder  = Color(0xFF1C2D3F);
const _spfAmber   = Color(0xFFF59E0B);
const _spfRed     = Color(0xFFEF4444);
const _spfText    = Color(0xFFA3B8CC);
const _spfMuted   = Color(0xFF3D5269);

TextStyle _jb({
  double size = 12,
  Color color = _spfText,
  FontWeight weight = FontWeight.w400,
  double? spacing,
}) => GoogleFonts.poppins(
  fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing,
);

class SecurityPulseFeed extends StatelessWidget {
  final _adminRepo = AdminRepository();
  SecurityPulseFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _adminRepo.streamSecurityAuditLog(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _spfAmber));
        }
        if (snapshot.hasError) {
          return Center(child: Text('ERROR LOADING FEED', style: _jb(color: _spfRed)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _spfAmber));
        }

        final logs = snapshot.data!.docs;

        if (logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, color: _spfAmber.withValues(alpha: 0.3), size: 40),
                const SizedBox(height: 16),
                Text('NO SECURITY EVENTS DETECTED', style: _jb(size: 11, color: _spfMuted, spacing: 2)),
              ],
            ),
          );
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: const BoxDecoration(
                color: _spfCard,
                border: Border(bottom: BorderSide(color: _spfBorder)),
              ),
              child: Row(
                children: [
                  SizedBox(width: 70, child: Text('TIME', style: _jb(size: 9, color: _spfMuted, spacing: 1.5))),
                  const SizedBox(width: 12),
                  Expanded(child: Text('EVENT', style: _jb(size: 9, color: _spfMuted, spacing: 1.5))),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: logs.length,
                itemBuilder: (context, i) {
                  final data = logs[i].data() as Map<String, dynamic>;
                  final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                  final event = (data['event'] as String?)?.trim();
                  final details = (data['details'] as String?)?.trim() ?? '';
                  return _SecurityLogTile(
                    event: event?.isNotEmpty == true ? event! : 'UNKNOWN_EVENT',
                    details: details,
                    timestamp: timestamp,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

String _formatTimestamp(DateTime ts) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tsDay = DateTime(ts.year, ts.month, ts.day);
  if (tsDay == today) return DateFormat('HH:mm:ss').format(ts);
  return DateFormat('MMM dd HH:mm').format(ts);
}

bool _isCritical(String event) =>
    event.contains('ERROR') ||
    event.contains('FAILURE') ||
    event.contains('WIPE') ||
    event.contains('kill_switch') ||
    event.contains('KILL') ||
    event.contains('aborted') ||
    event.contains('connection_lost');

class _SecurityLogTile extends StatelessWidget {
  final String event;
  final String details;
  final DateTime? timestamp;

  const _SecurityLogTile({
    required this.event,
    required this.details,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final critical = _isCritical(event);
    final accent = critical ? _spfRed : _spfAmber;
    final timeStr = timestamp != null ? _formatTimestamp(timestamp!) : '--:--:--';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: critical ? _spfRed.withValues(alpha: 0.05) : _spfCard,
            border: Border.all(color: _spfBorder),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timestamp column
                        SizedBox(
                          width: 70,
                          child: Text(timeStr, style: _jb(size: 10, color: _spfMuted)),
                        ),
                        const SizedBox(width: 12),
                        // Event + details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (critical) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      color: _spfRed,
                                      child: Text(
                                        'ALERT',
                                        style: _jb(
                                          size: 8,
                                          color: Colors.black,
                                          weight: FontWeight.w700,
                                          spacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      event.toUpperCase(),
                                      style: _jb(
                                        size: 12,
                                        color: accent,
                                        weight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (details.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  details,
                                  style: _jb(size: 11, color: _spfText),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
