import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failure.dart';
import '../../core/session/user_role.dart';
import '../admin_app.dart';
import '../providers/operations_providers.dart';

/// Account administration.
///
/// Lookup by id rather than a search box, and that is deliberate: there is no
/// user-search endpoint, and adding one would mean handing a helpdesk the
/// ability to enumerate patients by name. An operator acting on an account
/// already has its id — from a ticket, a report, or a review.
class UserAdminScreen extends ConsumerStatefulWidget {
  const UserAdminScreen({super.key});

  @override
  ConsumerState<UserAdminScreen> createState() => _UserAdminScreenState();
}

class _UserAdminScreenState extends ConsumerState<UserAdminScreen> {
  final _idController = TextEditingController();
  String? _lookingUp;
  bool _busy = false;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _act(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (_lookingUp != null) ref.invalidate(userLookupProvider(_lookingUp!));
      if (!mounted) return;
      _toast(done);
    } on Failure catch (f) {
      if (!mounted) return;
      _toast(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scopes = ref.watch(operatorScopesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Accounts', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Suspension takes effect on the account’s next request, not in '
            'fifteen minutes. Nothing here deletes anything — clinical records '
            'outlive an account by law.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _idController,
                  decoration: const InputDecoration(
                    labelText: 'User id',
                    hintText: 'From a ticket, a report, or the review queue',
                  ),
                  onSubmitted: (v) => setState(
                      () => _lookingUp = v.trim().isEmpty ? null : v.trim()),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => setState(() {
                  final v = _idController.text.trim();
                  _lookingUp = v.isEmpty ? null : v;
                }),
                child: const Text('Look up'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_lookingUp == null)
            const Expanded(
              child: Center(
                child: Text('Enter a user id to see the account.'),
              ),
            )
          else
            Expanded(
              child: ref.watch(userLookupProvider(_lookingUp!)).when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text(
                        e is Failure
                            ? e.message
                            : 'Could not load that account.',
                      ),
                    ),
                    data: (user) => _Account(
                      user: user,
                      busy: _busy,
                      scopes: scopes,
                      onSuspend: (status, reason) => _act(
                        () => ref
                            .read(operationsRepositoryProvider)
                            .suspendAccount(
                              _lookingUp!,
                              status: status,
                              reason: reason,
                            ),
                        'Account ${status.label.toLowerCase()}.',
                      ),
                      onReactivate: () => _act(
                        () => ref
                            .read(operationsRepositoryProvider)
                            .reactivateAccount(_lookingUp!),
                        'Account reactivated.',
                      ),
                      onRole: (role) => _act(
                        () => ref
                            .read(operationsRepositoryProvider)
                            .assignRole(_lookingUp!, role),
                        'Role changed to ${role.label}.',
                      ),
                    ),
                  ),
            ),
        ],
      ),
    );
  }
}

class _Account extends StatelessWidget {
  const _Account({
    required this.user,
    required this.busy,
    required this.scopes,
    required this.onSuspend,
    required this.onReactivate,
    required this.onRole,
  });

  final Map<String, dynamic> user;
  final bool busy;
  final Set<String> scopes;
  final void Function(AccountStatus, String reason) onSuspend;
  final VoidCallback onReactivate;
  final void Function(UserRole) onRole;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = AccountStatus.fromWire(user['status'] as String?);
    final role = UserRole.fromWire(user['role'] as String?);

    return ListView(
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Name'),
                trailing: Text(user['displayName'] as String? ?? '—'),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Role'),
                trailing: Text(role.label),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Account status'),
                trailing: Text(status.label),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Provider status'),
                trailing: Text(
                  ProviderStatus.fromWire(user['providerStatus'] as String?)
                      .label,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Contact'),
                trailing: Text(
                  [
                    if (user['email'] != null) user['email'] as String,
                    if (user['phone'] != null) user['phone'] as String,
                  ].join('  ·  '),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (scopes.canSuspendAccounts) ...[
          Text('Account actions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (status == AccountStatus.active) ...[
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => _askReason(
                                context,
                                AccountStatus.suspended,
                                onSuspend,
                              ),
                      child: const Text('Suspend'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => _askReason(
                                context,
                                AccountStatus.deactivated,
                                onSuspend,
                              ),
                      child: Text(
                        'Deactivate',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ] else
                    FilledButton(
                      onPressed: busy ? null : onReactivate,
                      child: const Text('Reactivate'),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (scopes.canAssignRoles) ...[
          const SizedBox(height: 20),
          Text('Role', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The most dangerous action in this console. Granting Supervisor '
            'hands someone the power to approve doctors.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in UserRole.values)
                    if (r != role)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => _confirmRole(context, r, onRole),
                        child: Text(r.label),
                      ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  static Future<void> _askReason(
    BuildContext context,
    AccountStatus status,
    void Function(AccountStatus, String) onConfirm,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${status.label} this account'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason',
              helperText: 'Recorded against the account and shown to the user.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(status.label),
          ),
        ],
      ),
    );
    controller.dispose();

    if (reason != null && reason.length >= 4) onConfirm(status, reason);
  }

  static Future<void> _confirmRole(
    BuildContext context,
    UserRole role,
    void Function(UserRole) onConfirm,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Make this account ${role.label}?'),
        content: Text(
          role == UserRole.supervisor || role == UserRole.admin
              ? 'This grants the power to approve doctors and act on other '
                  'accounts. Only do this for someone who should have it.'
              : 'This changes what the account can do on their next request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Change role'),
          ),
        ],
      ),
    );

    if (ok == true) onConfirm(role);
  }
}
