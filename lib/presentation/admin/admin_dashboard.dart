import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/repositories/admin_repository.dart';
import 'widgets/connection_node_map.dart';
import 'widgets/security_pulse_feed.dart';
import 'widgets/transfer_volume_chart.dart';
import 'widgets/user_management_list.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg      = Color(0xFF080C10);
const _surface = Color(0xFF0D1520);
const _card    = Color(0xFF111B28);
const _amber   = Color(0xFFF59E0B);
const _emerald = Color(0xFF10B981);
const _red     = Color(0xFFEF4444);
const _text    = Color(0xFFA3B8CC);
const _muted   = Color(0xFF3D5269);
const _border  = Color(0xFF1C2D3F);

// ── Typography ────────────────────────────────────────────────────────────────
TextStyle _jb({
  double size = 13,
  Color color = _text,
  FontWeight weight = FontWeight.w400,
  double? spacing,
}) => GoogleFonts.jetBrainsMono(
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: spacing,
);

// ── Theme ─────────────────────────────────────────────────────────────────────
ThemeData _terminalTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: _bg,
    colorScheme: const ColorScheme.dark(
      surface: _surface,
      primary: _amber,
      secondary: _emerald,
      error: _red,
      onSurface: _text,
      outline: _border,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      tertiary: Color(0xFF60A5FA),
      onTertiary: Colors.black,
      onError: Colors.black,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: _amber),
    dividerColor: _border,
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: _amber),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _border),
      ),
    ),
  );
}

// ── Root ──────────────────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _adminRepo = AdminRepository();
  final _networkKey = GlobalKey<ConnectionNodeMapState>();
  late final Stream<QuerySnapshot> _transferLogsStream;
  late final Stream<DateTime> _clock;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(_onTabChanged);
    _transferLogsStream = _adminRepo.streamTransferLogsDetail();
    _clock = Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now().toUtc());
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && !_tabController.indexIsChanging) {
      _networkKey.currentState?.refresh();
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _terminalTheme(),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(
          children: [
            _CommandHeader(clock: _clock, tabController: _tabController),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _AnalyticsTab(
                    adminRepo: _adminRepo,
                    transferLogsStream: _transferLogsStream,
                  ),
                  ConnectionNodeMap(key: _networkKey),
                  SecurityPulseFeed(),
                  const UserManagementList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Command Header ─────────────────────────────────────────────────────────────
class _CommandHeader extends StatelessWidget {
  final Stream<DateTime> clock;
  final TabController tabController;
  const _CommandHeader({required this.clock, required this.tabController});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _surface,
          border: Border(bottom: BorderSide(color: _border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 20, 0),
              child: Row(
                children: [
                  // Back
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        border: Border.all(color: _border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: _muted, size: 13),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Title
                  Expanded(
                    child: Text(
                      'CRYPTRANSFER // COMMAND',
                      style: _jb(size: 13, color: _amber, weight: FontWeight.w700, spacing: 2.5),
                    ),
                  ),
                  // Live UTC clock
                  StreamBuilder<DateTime>(
                    stream: clock,
                    builder: (_, snap) {
                      final t = snap.data ?? DateTime.now().toUtc();
                      final s = '${_p(t.hour)}:${_p(t.minute)}:${_p(t.second)} UTC';
                      return Text(s, style: _jb(size: 11, color: _muted));
                    },
                  ),
                ],
              ),
            ),
            // Status line
            Padding(
              padding: const EdgeInsets.fromLTRB(50, 6, 20, 12),
              child: Row(
                children: [
                  _StatusDot(),
                  const SizedBox(width: 8),
                  Text('ALL SYSTEMS NOMINAL',
                      style: _jb(size: 10, color: _emerald, spacing: 2.0)),
                ],
              ),
            ),
            // Tab bar
            TabBar(
              controller: tabController,
              indicatorColor: _amber,
              indicatorWeight: 2,
              dividerColor: Colors.transparent,
              labelStyle: _jb(size: 11, color: _amber, weight: FontWeight.w700, spacing: 1.5),
              unselectedLabelStyle: _jb(size: 11, color: _muted, spacing: 1.5),
              tabs: const [
                Tab(text: 'ANALYTICS'),
                Tab(text: 'NETWORK'),
                Tab(text: 'SECURITY'),
                Tab(text: 'USERS'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ── Status Dot ────────────────────────────────────────────────────────────────
class _StatusDot extends StatefulWidget {
  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.of(context).disableAnimations) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _emerald,
          boxShadow: [
            BoxShadow(
              color: _emerald.withValues(alpha: 0.25 + 0.5 * _ctrl.value),
              blurRadius: 6 + 10 * _ctrl.value,
              spreadRadius: 1 + 2 * _ctrl.value,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Analytics Tab ─────────────────────────────────────────────────────────────
class _AnalyticsTab extends StatelessWidget {
  final AdminRepository adminRepo;
  final Stream<QuerySnapshot> transferLogsStream;
  const _AnalyticsTab({required this.adminRepo, required this.transferLogsStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: transferLogsStream,
      builder: (context, snapshot) {
        final docs = snapshot.hasData
            ? snapshot.data!.docs
                .map((d) => d.data() as Map<String, dynamic>)
                .toList()
            : <Map<String, dynamic>>[];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Stat cards
              Row(
                children: [
                  Expanded(
                    child: StreamBuilder<int>(
                      stream: adminRepo.streamTotalTransfers(),
                      builder: (_, s) => _StatCard(
                        label: 'TRANSFERS',
                        value: s.data?.toString() ?? '—',
                        icon: Icons.swap_horiz_rounded,
                        accent: _amber,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StreamBuilder<int>(
                      stream: adminRepo.streamTotalUsers(),
                      builder: (_, s) => _StatCard(
                        label: 'USERS',
                        value: s.data?.toString() ?? '—',
                        icon: Icons.people_rounded,
                        accent: _emerald,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),
              _SectionLabel('TRANSFER VOLUME — 7D'),
              const SizedBox(height: 12),

              // Chart
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()))
                    : snapshot.hasError
                        ? SizedBox(
                            height: 200,
                            child: Center(
                              child: Text('ERROR LOADING DATA',
                                  style: _jb(color: _red)),
                            ),
                          )
                        : TransferVolumeChart(docs: docs),
              ),

              const SizedBox(height: 32),
              _SectionLabel('TRANSFER LOG'),
              const SizedBox(height: 12),
              _TransferLog(snapshot: snapshot, context: context),

              const SizedBox(height: 32),
              _SectionLabel('ACTIVE HANDSHAKES'),
              const SizedBox(height: 12),
              _ActiveHandshakes(adminRepo: adminRepo),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 14),
              const SizedBox(width: 8),
              Text(label, style: _jb(size: 9, color: _muted, spacing: 2)),
            ],
          ),
          const SizedBox(height: 14),
          Text(value,
              style: _jb(size: 38, color: accent, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withValues(alpha: 0.7), Colors.transparent],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Label ─────────────────────────────────────────────────────────────
Widget _SectionLabel(String label) => Row(
      children: [
        Container(width: 3, height: 13, color: _amber),
        const SizedBox(width: 10),
        Text(label, style: _jb(size: 10, color: _muted, spacing: 2)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: _border)),
      ],
    );

// ── Transfer Log ──────────────────────────────────────────────────────────────
class _TransferLog extends StatelessWidget {
  final AsyncSnapshot<QuerySnapshot> snapshot;
  final BuildContext context;
  const _TransferLog({required this.snapshot, required this.context});

  @override
  Widget build(BuildContext ctx) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError || !snapshot.hasData) {
      return _shell(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(child: Text('ERROR LOADING LOG', style: _jb(color: _red))),
        ),
      );
    }
    final docs = snapshot.data!.docs;
    if (docs.isEmpty) {
      return _shell(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(child: Text('NO RECORDS', style: _jb(color: _muted))),
        ),
      );
    }

    return _shell(
      Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
              color: _surface,
            ),
            child: Row(
              children: [
                SizedBox(
                    width: 62, child: Text('TIME', style: _jb(size: 9, color: _muted, spacing: 1.5))),
                const SizedBox(width: 12),
                SizedBox(
                    width: 80, child: Text('STATUS', style: _jb(size: 9, color: _muted, spacing: 1.5))),
                const SizedBox(width: 12),
                Expanded(child: Text('ROUTE', style: _jb(size: 9, color: _muted, spacing: 1.5))),
                Text('FILE', style: _jb(size: 9, color: _muted, spacing: 1.5)),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              return _TransferRow(
                data: data,
                onTap: () => _showDetail(ctx, data),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _shell(Widget child) => Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border),
        ),
        clipBehavior: Clip.hardEdge,
        child: child,
      );

  void _showDetail(BuildContext ctx, Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'unknown';
    final (statusColor, statusLabel) = _statusInfo(status);
    final fileSize = data['fileSize'] as int? ?? 0;
    final ts = (data['loggedAt'] as Timestamp?)?.toDate();

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(
                      color: _border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('TRANSFER DETAIL',
                    style: _jb(size: 12, color: _amber, weight: FontWeight.w700, spacing: 2)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(statusLabel,
                      style: _jb(size: 9, color: statusColor, weight: FontWeight.w700, spacing: 0.5)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(height: 1, color: _border),
            const SizedBox(height: 16),
            _DetailLine('SENDER', '@${data['senderUsername'] ?? '?'}'),
            _DetailLine('RECEIVER', '@${data['receiverUsername'] ?? '?'}'),
            _DetailLine('FILE', data['fileName'] as String? ?? '—'),
            _DetailLine('SIZE', fileSize > 0 ? _fmtBytes(fileSize) : '—'),
            if (ts != null) _DetailLine('LOGGED', _fmtTsFull(ts)),
            _DetailLine('SENDER UID', data['senderId'] as String? ?? '—', mono: true),
            _DetailLine('RECEIVER UID', data['receiverId'] as String? ?? '—', mono: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Transfer Row ──────────────────────────────────────────────────────────────
class _TransferRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _TransferRow({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sender   = data['senderUsername'] as String? ?? '?';
    final receiver = data['receiverUsername'] as String? ?? '?';
    final fileName = data['fileName'] as String? ?? '—';
    final status   = data['status'] as String? ?? 'unknown';
    final ts       = (data['loggedAt'] as Timestamp?)?.toDate();
    final timeStr  = ts != null
        ? '${_p(ts.hour)}:${_p(ts.minute)}:${_p(ts.second)}'
        : '--:--:--';
    final (statusColor, statusLabel) = _statusInfo(status);

    return InkWell(
      onTap: onTap,
      hoverColor: _amber.withValues(alpha: 0.03),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _border, width: 1)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Text(timeStr, style: _jb(size: 10, color: _muted)),
            ),
            const SizedBox(width: 12),
            Container(
              width: 80,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                statusLabel,
                style: _jb(size: 9, color: statusColor, weight: FontWeight.w700, spacing: 0.4),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '@$sender → @$receiver',
                style: _jb(size: 12, color: _text),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              fileName,
              style: _jb(size: 10, color: _muted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ── Active Handshakes ─────────────────────────────────────────────────────────
class _ActiveHandshakes extends StatefulWidget {
  final AdminRepository adminRepo;
  const _ActiveHandshakes({required this.adminRepo});

  @override
  State<_ActiveHandshakes> createState() => _ActiveHandshakesState();
}

class _ActiveHandshakesState extends State<_ActiveHandshakes> {
  late final Stream<QuerySnapshot> _handshakesStream;

  @override
  void initState() {
    super.initState();
    _handshakesStream = widget.adminRepo.streamActiveHandshakesDetail();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _handshakesStream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || !snap.hasData) {
          return _shell(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('ERROR', style: _jb(color: _red))),
            ),
          );
        }
        final sessions = snap.data!.docs;
        if (sessions.isEmpty) {
          return _shell(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('NO ACTIVE HANDSHAKES', style: _jb(color: _muted))),
            ),
          );
        }
        return _shell(
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sessions.length,
            itemBuilder: (_, i) {
              final data = sessions[i].data() as Map<String, dynamic>;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _border)),
                ),
                child: Row(
                  children: [
                    _LiveDot(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '@${data['fromUsername'] ?? '...'} ──── @${data['toUsername'] ?? '...'}',
                        style: _jb(size: 12, color: _text),
                      ),
                    ),
                    Text('ESTABLISHED',
                        style: _jb(size: 9, color: _emerald, spacing: 1.5)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _shell(Widget child) => Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border),
        ),
        clipBehavior: Clip.hardEdge,
        child: child,
      );
}

// ── Live Dot ──────────────────────────────────────────────────────────────────
class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.of(context).disableAnimations) {
      if (!_ctrl.isAnimating) _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _emerald,
          boxShadow: [
            BoxShadow(
              color: _emerald.withValues(alpha: 0.3 + 0.4 * _ctrl.value),
              blurRadius: 6 + 8 * _ctrl.value,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail Line ───────────────────────────────────────────────────────────────
class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _DetailLine(this.label, this.value, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: _jb(size: 10, color: _muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: _jb(size: 11, color: mono ? _amber : _text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
(Color, String) _statusInfo(String status) => switch (status) {
  'completed'       => (_emerald, 'COMPLETE'),
  'kill_switch'     => (_red,     'KILL_SW'),
  'aborted'         => (_red,     'ABORTED'),
  'connection_lost' => (_red,     'CONN_ERR'),
  'failed'          => (_red,     'FAILED'),
  'started'         => (_amber,   'ACTIVE'),
  _                 => (_muted,   'UNKNOWN'),
};

String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _fmtTsFull(DateTime ts) {
  const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final p = (int n) => n.toString().padLeft(2, '0');
  return '${mo[ts.month - 1]} ${ts.day}, ${ts.year}  ${p(ts.hour)}:${p(ts.minute)}:${p(ts.second)}';
}
