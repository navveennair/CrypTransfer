import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app_theme.dart';
import '../../data/repositories/admin_repository.dart';
import '../widgets/shared_widgets.dart';
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
  final _adminRepo = AdminRepository();

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
    return Theme(
      data: AppTheme.dark,
      child: Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;

        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'CrypTransferAdmin',
              style: tt.titleMedium?.copyWith(
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
              labelStyle: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
              unselectedLabelStyle: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
              labelColor: cs.primary,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
              tabs: const [
                Tab(text: 'ANALYTICS'),
                Tab(text: 'NETWORK'),
                Tab(text: 'SECURITY'),
                Tab(text: 'USERS'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildAnalyticsTab(cs, tt),
              ConnectionNodeMap(),
              SecurityPulseFeed(),
              const UserManagementList(),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildAnalyticsTab(ColorScheme cs, TextTheme tt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryCards(cs),
          const SizedBox(height: 24),

          Text(
            'NETWORK VOLUME',
            style: tt.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: TransferVolumeChart(),
          ),

          const SizedBox(height: 32),
          Text(
            'ACTIVE HANDSHAKES',
            style: tt.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          _buildActiveSessionsList(cs, tt),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(ColorScheme cs) {
    return StreamBuilder<int>(
      stream: _adminRepo.streamTotalTransfers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            children: [
              _SummaryCard(label: 'TRANSFERS', value: '–', icon: Icons.swap_horiz_rounded, color: cs.primary),
              const SizedBox(width: 16),
              _SummaryCard(label: 'TOTAL NODES', value: '–', icon: Icons.hub_rounded, color: cs.secondary),
            ],
          );
        }
        if (snapshot.hasError) {
          return Row(
            children: [
              _SummaryCard(label: 'TRANSFERS', value: '–', icon: Icons.swap_horiz_rounded, color: cs.error),
              const SizedBox(width: 16),
              _SummaryCard(label: 'TOTAL NODES', value: '–', icon: Icons.hub_rounded, color: cs.error),
            ],
          );
        }
        final totalTransfers = snapshot.data ?? 0;

        return Row(
          children: [
            _SummaryCard(
              label: 'TRANSFERS',
              value: totalTransfers.toString(),
              icon: Icons.swap_horiz_rounded,
              color: cs.primary,
            ),
            const SizedBox(width: 16),
            StreamBuilder<int>(
              stream: _adminRepo.streamTotalUsers(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return _SummaryCard(label: 'TOTAL NODES', value: '–', icon: Icons.hub_rounded, color: cs.secondary);
                }
                if (userSnap.hasError) {
                  return _SummaryCard(label: 'TOTAL NODES', value: '–', icon: Icons.hub_rounded, color: cs.error);
                }
                final totalUsers = userSnap.data ?? 0;
                return _SummaryCard(
                  label: 'TOTAL NODES',
                  value: totalUsers.toString(),
                  icon: Icons.hub_rounded,
                  color: cs.secondary,
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildActiveSessionsList(ColorScheme cs, TextTheme tt) {
    return StreamBuilder<QuerySnapshot>(
      stream: _adminRepo.streamActiveHandshakesDetail(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Error loading data',
                style: TextStyle(color: cs.error),
              ),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final sessions = snapshot.data!.docs;

        if (sessions.isEmpty) {
          return GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No active P2P handshakes',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sessions.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final data = sessions[i].data() as Map<String, dynamic>;
            return GlassContainer(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${data['fromUsername'] ?? '...'} → @${data['toUsername'] ?? '...'}',
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Handshake established',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _PulseIndicator(color: Theme.of(context).colorScheme.secondary),
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
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 16),
            Text(
              value,
              style: tt.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: cs.onSurface.withValues(alpha: 0.6),
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
