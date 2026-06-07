import 'package:flutter/material.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/user_model.dart';

/// Route-level guard for the /admin-dashboard route.
///
/// Streams [AuthRepository.streamUserProfile] and:
/// - Shows a loading scaffold while the stream is pending.
/// - Redirects to '/' with an 'Access denied' SnackBar if the user is not an admin.
/// - Redirects silently to '/' if no user is authenticated.
/// - Renders [child] when [UserModel.isAdmin] is true.
///
/// Implemented as a [StatefulWidget] so that [AuthRepository] is instantiated
/// once and [streamUserProfile] is subscribed once in [initState], preventing
/// listener leaks on rebuild (CR-02).
///
/// All navigation uses [WidgetsBinding.instance.addPostFrameCallback] to
/// avoid "setState called during build" errors (D-01/D-02/D-03).
class AdminGuard extends StatefulWidget {
  final Widget child;

  const AdminGuard({super.key, required this.child});

  @override
  State<AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<AdminGuard> {
  final _authRepo = AuthRepository();
  Stream<UserModel?>? _profileStream;

  @override
  void initState() {
    super.initState();
    final uid = _authRepo.currentUser?.uid;
    if (uid != null) {
      _profileStream = _authRepo.streamUserProfile(uid);
    }
  }

  Widget _loadingScaffold(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: const Center(child: CircularProgressIndicator()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // State A: no authenticated user at initState time — redirect silently, no SnackBar
    if (_profileStream == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      });
      return _loadingScaffold(context);
    }

    // States B/C/D: authenticated user — stream isAdmin status (single subscription)
    return StreamBuilder<UserModel?>(
      stream: _profileStream,
      builder: (context, snapshot) {
        // State B: stream loading
        if (!snapshot.hasData && !snapshot.hasError) {
          return _loadingScaffold(context);
        }

        // State C: error or non-admin — redirect with SnackBar
        if (snapshot.hasError || snapshot.data?.isAdmin != true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Access denied'),
                  duration: Duration(seconds: 3),
                ),
              );
              Navigator.pushReplacementNamed(context, '/');
            }
          });
          return _loadingScaffold(context);
        }

        // State D: admin confirmed — render child
        return widget.child;
      },
    );
  }
}
