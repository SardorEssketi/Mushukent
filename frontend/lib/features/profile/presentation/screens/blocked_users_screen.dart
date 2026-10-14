import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../application/blocking.dart';

final blockedUsersProvider =
    FutureProvider.autoDispose<List<BlockedUserData>>((ref) {
  return ref.watch(mushukistanApiProvider).listBlockedUsers();
});

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  final Set<String> _unblocking = <String>{};

  Future<void> _unblock(BlockedUserData user) async {
    if (_unblocking.contains(user.id)) return;
    final strings = ref.read(appStringsProvider);
    setState(() => _unblocking.add(user.id));
    try {
      await ref.read(mushukistanApiProvider).unblockUser(user.id);
      refreshAfterBlockChange(ref);
      ref.invalidate(blockedUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.userUnblocked)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.couldNotUpdateBlock)));
      }
    } finally {
      if (mounted) setState(() => _unblocking.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final blocked = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.blockedUsers)),
      body: blocked.when(
        data: (users) {
          if (users.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(strings.blockedUsersEmpty),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(blockedUsersProvider.future),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = users[index];
                final name = user.name ?? strings.unnamedUser;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user.avatarUrl == null
                        ? null
                        : NetworkImage(user.avatarUrl!),
                    child: user.avatarUrl == null
                        ? Text(name.characters.first.toUpperCase())
                        : null,
                  ),
                  title: Text(name),
                  trailing: OutlinedButton(
                    onPressed: _unblocking.contains(user.id)
                        ? null
                        : () => _unblock(user),
                    child: Text(strings.unblockUser),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.couldNotLoadSection),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(blockedUsersProvider),
                child: Text(strings.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
