import 'package:flutter/material.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../widgets/shared_widgets.dart';

class UserManagementList extends StatelessWidget {
  const UserManagementList({super.key});

  @override
  Widget build(BuildContext context) {
    final adminRepo = AdminRepository();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return StreamBuilder<List<UserModel>>(
      stream: adminRepo.streamAllUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading data',
              style: TextStyle(color: cs.error),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final users = snapshot.data!.where((u) =>
          u.username.isNotEmpty &&
          u.email.isNotEmpty &&
          u.username != '@'
        ).toList();

        if (users.isEmpty) {
          return Center(
            child: Text(
              'No valid users found',
              style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          itemCount: users.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, i) {
            final user = users[i];
            final isSecured = user.hasPublicKey;

            return GlassContainer(
              padding: const EdgeInsets.all(16),
              borderColor: user.isActive
                  ? (isSecured ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant)
                  : cs.error.withValues(alpha: 0.3),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (user.isAdmin ? cs.tertiary : cs.primary).withValues(alpha: 0.1),
                      border: Border.all(
                        color: (user.isAdmin ? cs.tertiary : cs.primary).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Icon(
                      isSecured ? Icons.shield_rounded : (user.isAdmin ? Icons.admin_panel_settings : Icons.person_rounded),
                      color: user.isAdmin ? cs.tertiary : cs.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${user.username}',
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _RevokeButton(
                    user: user,
                    onToggle: (val) => adminRepo.setUserActiveStatus(user.uid, val),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RevokeButton extends StatelessWidget {
  final UserModel user;
  final Function(bool) onToggle;

  const _RevokeButton({required this.user, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (user.isAdmin) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.tertiary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'ADMIN',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.tertiary,
          ),
        ),
      );
    }

    return Switch(
      value: user.isActive,
      activeThumbColor: cs.secondary,
      activeTrackColor: cs.secondary.withValues(alpha: 0.2),
      inactiveThumbColor: cs.error,
      inactiveTrackColor: cs.error.withValues(alpha: 0.2),
      onChanged: onToggle,
    );
  }
}
