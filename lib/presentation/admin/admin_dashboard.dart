import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firebase_constants.dart';
import 'widgets/security_pulse_feed.dart';
import 'widgets/transfer_volume_chart.dart';
import 'widgets/connection_node_map.dart';
import 'widgets/user_management_list.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'CRYPTRANSFER COMMAND',
          style: GoogleFonts.orbitron(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: cs.primary,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: cs.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.bold, 
            fontSize: 12,
            color: cs.onSurface,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w500, 
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
          labelColor: cs.onSurface,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: const [
            Tab(text: 'ANALYTICS', icon: Icon(Icons.analytics_outlined)),
            Tab(text: 'NETWORK', icon: Icon(Icons.hub_outlined)),
            Tab(text: 'SECURITY', icon: Icon(Icons.security_outlined)),
            Tab(text: 'USERS', icon: Icon(Icons.manage_accounts_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAnalyticsTab(cs),
          const ConnectionNodeMap(),
          const SecurityPulseFeed(),
          const UserManagementList(),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(cs),
          const SizedBox(height: 32),
          Text(
            'Transfer Volume (24h)',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          const TransferVolumeChart(),
          const SizedBox(height: 32),
          Text(
            'Active Handshake Sessions',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _buildActiveSessionsList(cs),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(ColorScheme cs) {
    return StreamBuilder<QuerySnapshot>(
      // TOP-LEVEL COLLECTION: transfer_logs
      stream: FirebaseFirestore.instance.collection(FirebaseConstants.transferLogs).snapshots(),
      builder: (context, snapshot) {
        final totalTransfers = snapshot.data?.size ?? 0;
        
        return Row(
          children: [
            _SummaryCard(
              label: 'TOTAL TRANSFERS',
              value: totalTransfers.toString(),
              icon: Icons.swap_horiz_rounded,
              color: cs.primary,
            ),
            const SizedBox(width: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection(FirebaseConstants.users).snapshots(),
              builder: (context, userSnap) {
                final totalUsers = userSnap.data?.size ?? 0;
                return _SummaryCard(
                  label: 'TOTAL NODES',
                  value: totalUsers.toString(),
                  icon: Icons.person_outline_rounded,
                  color: cs.tertiary,
                );
              },
            ),
          ],
        );
      }
    );
  }

  Widget _buildActiveSessionsList(ColorScheme cs) {
    return StreamBuilder<QuerySnapshot>(
      // TOP-LEVEL COLLECTION: handshakes
      stream: FirebaseFirestore.instance
          .collection(FirebaseConstants.handshakes)
          .where('status', isEqualTo: 'handshake_complete')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final sessions = snapshot.data!.docs;
        
        if (sessions.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline),
            ),
            child: Center(
              child: Text(
                'No active P2P handshakes',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sessions.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final data = sessions[i].data() as Map<String, dynamic>;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, color: Colors.greenAccent),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Session: @${data['fromUsername'] ?? '...'} -> @${data['toUsername'] ?? '...'}',
                          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Handshake ID: ${sessions[i].id}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const _PulseIndicator(color: Colors.greenAccent),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 16),
            Text(
              value,
              style: GoogleFonts.orbitron(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseIndicator extends StatefulWidget {
  final Color color;
  const _PulseIndicator({required this.color});

  @override
  State<_PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<_PulseIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
