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
/// All navigation uses [WidgetsBinding.instance.addPostFrameCallback] to
/// avoid "setState called during build" errors (D-01/D-02/D-03).
class AdminGuard extends StatelessWidget {
  final Widget child;

  const AdminGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final authRepo = AuthRepository();
    final user = authRepo.currentUser;

    Widget loadingScaffold() => Scaffold(
          backgroundColor: cs.surface,
          body: const Center(child: CircularProgressIndicator()),
        );

    // State A: no authenticated user — redirect silently, no SnackBar
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      });
      return loadingScaffold();
    }

    // States B/C/D: authenticated user — stream isAdmin status
    return StreamBuilder<UserModel?>(
      stream: authRepo.streamUserProfile(user.uid),
      builder: (context, snapshot) {
        // State B: stream loading
        if (!snapshot.hasData && !snapshot.hasError) {
          return loadingScaffold();
        }

        // State C: error or non-admin — redirect with SnackBar
        if (snapshot.hasError || snapshot.data?.isAdmin != true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Access denied'),
                  duration: Duration(seconds: 3),
                ),
              );
              Navigator.pushReplacementNamed(context, '/');
            }
          });
          return loadingScaffold();
        }

        // State D: admin confirmed — render child
        return child;
      },
    );
  }
}
