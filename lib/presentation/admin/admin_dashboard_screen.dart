import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_theme.dart';
import '../../data/repositories/admin_repository.dart';
import '../widgets/shared_widgets.dart';

class AdminDashboardScreen extends StatelessWidget {
  final _adminRepo = AdminRepository();

  AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark,
      child: Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;

        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'Transfer Logs',
              style: GoogleFonts.orbitron(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: cs.primary,
              ),
            ),
            centerTitle: true,
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: _adminRepo.streamTransferLogsDetail(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(color: cs.error),
                  ),
                );
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'No transfer logs found.',
                    style: GoogleFonts.exo2(color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final sender = data['senderUsername'] ?? 'Unknown';
                  final receiver = data['receiverUsername'] ?? 'Unknown';
                  final fileName = data['fileName'] ?? 'File';
                  final date = data['transferDate'] ?? '';
                  final time = data['transferTime'] ?? '';

                  return GlassContainer(
                    padding: const EdgeInsets.all(16),
                    borderRadius: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.swap_horiz_rounded, color: cs.primary, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '@$sender → @$receiver',
                                style: GoogleFonts.orbitron(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: cs.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          fileName,
                          style: GoogleFonts.exo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$date  $time'.trim(),
                          style: GoogleFonts.exo2(
                            fontSize: 10,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      }),
    );
  }
}
