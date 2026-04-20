import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/admin_repository.dart';

class UserManagementList extends StatelessWidget {
  const UserManagementList({super.key});

  @override
  Widget build(BuildContext context) {
    final adminRepo = AdminRepository();
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<UserModel>>(
      stream: adminRepo.streamAllUsers(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!;

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: users.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final user = users[i];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: user.isActive ? cs.outline : Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: user.isAdmin ? cs.tertiary : cs.primary.withValues(alpha: 0.1),
                    child: Icon(
                      user.isAdmin ? Icons.admin_panel_settings : Icons.person,
                      color: user.isAdmin ? Colors.white : cs.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${user.username}',
                          style: GoogleFonts.poppins(
                            color: cs.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          user.email,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  _RevokeButton(user: user, onToggle: (val) => adminRepo.setUserActiveStatus(user.uid, val)),
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
    if (user.isAdmin) return const SizedBox.shrink(); // Cannot revoke other admins easily here

    return Switch(
      value: user.isActive,
      activeThumbColor: Colors.green,
      activeTrackColor: Colors.green.withValues(alpha: 0.3),
      inactiveThumbColor: Colors.red,
      inactiveTrackColor: Colors.red.withValues(alpha: 0.3),
      onChanged: onToggle,
    );
  }
}
