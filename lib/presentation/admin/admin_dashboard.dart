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
  final _networkKey = GlobalKey<ConnectionNodeMapState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    // index 1 = NETWORK tab; refresh when user switches to it
    if (_tabController.index == 1 && !_tabController.indexIsChanging) {
      _networkKey.currentState?.refresh();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
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
              ConnectionNodeMap(key: _networkKey),
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
            'RECENT TRANSFERS',
            style: tt.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          _buildRecentTransfersList(cs, tt),

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
          const SizedBox(height: 24),
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

  Widget _buildRecentTransfersList(ColorScheme cs, TextTheme tt) {
    return StreamBuilder<QuerySnapshot>(
      stream: _adminRepo.streamTransferLogsDetail(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('Error loading data', style: TextStyle(color: cs.error))),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text('No transfer records yet', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (context, i) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final sender = data['senderUsername'] as String? ?? '?';
            final receiver = data['receiverUsername'] as String? ?? '?';
            final fileName = data['fileName'] as String? ?? 'Unknown file';
            final status = data['status'] as String? ?? 'unknown';
            final ts = (data['loggedAt'] as Timestamp?)?.toDate();

            final (statusColor, statusIcon) = _statusStyle(status, cs);

            return GlassContainer(
              padding: const EdgeInsets.all(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showTransferDetail(context, data, cs, tt),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 18),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '@$sender → @$receiver',
                            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fileName,
                            style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: tt.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (ts != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatLogTs(ts),
                            style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.4)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showTransferDetail(BuildContext context, Map<String, dynamic> data, ColorScheme cs, TextTheme tt) {
    final status = data['status'] as String? ?? 'unknown';
    final (statusColor, _) = _statusStyle(status, cs);
    final fileSize = data['fileSize'] as int? ?? 0;
    final ts = (data['loggedAt'] as Timestamp?)?.toDate();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 10),
                Text(
                  'TRANSFER DETAIL',
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.5, color: cs.primary),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: tt.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _DetailRow(label: 'Sender', value: '@${data['senderUsername'] ?? '?'}', cs: cs, tt: tt),
            _DetailRow(label: 'Receiver', value: '@${data['receiverUsername'] ?? '?'}', cs: cs, tt: tt),
            _DetailRow(label: 'File', value: data['fileName'] as String? ?? '—', cs: cs, tt: tt),
            _DetailRow(label: 'Size', value: fileSize > 0 ? _formatBytes(fileSize) : '—', cs: cs, tt: tt),
            if (ts != null)
              _DetailRow(label: 'Logged at', value: _formatLogTsFull(ts), cs: cs, tt: tt),
            _DetailRow(label: 'Sender UID', value: data['senderId'] as String? ?? '—', cs: cs, tt: tt, mono: true),
            _DetailRow(label: 'Receiver UID', value: data['receiverId'] as String? ?? '—', cs: cs, tt: tt, mono: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  (Color, IconData) _statusStyle(String status, ColorScheme cs) => switch (status) {
    'completed'       => (cs.secondary, Icons.check_circle_rounded),
    'aborted'         => (cs.error, Icons.cancel_rounded),
    'kill_switch'     => (cs.error, Icons.security_rounded),
    'connection_lost' => (cs.error, Icons.wifi_off_rounded),
    'failed'          => (cs.error, Icons.error_rounded),
    'started'         => (cs.primary, Icons.upload_rounded),
    _                 => (cs.onSurface.withValues(alpha: 0.5), Icons.circle_outlined),
  };

  String _formatLogTs(DateTime ts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tsDay = DateTime(ts.year, ts.month, ts.day);
    if (tsDay == today) {
      return '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    }
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[ts.month - 1]} ${ts.day}';
  }

  String _formatLogTsFull(DateTime ts) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[ts.month - 1]} ${ts.day}, ${ts.year}  '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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


class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;
  final bool mono;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.cs,
    required this.tt,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: mono
                  ? TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    )
                  : tt.bodySmall?.copyWith(color: cs.onSurface),
            ),
          ),
        ],
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
