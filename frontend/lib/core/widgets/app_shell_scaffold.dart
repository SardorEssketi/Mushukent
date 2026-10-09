import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../localization/app_strings.dart';
import '../navigation/tab_actions.dart';
import '../navigation/settings_changes_guard.dart';
import '../onboarding/authenticated_onboarding_flow.dart';
import '../../features/lost_pets/presentation/widgets/lost_pet_follow_up_listener.dart';

class AppShellScaffold extends ConsumerWidget {
  const AppShellScaffold({
    super.key,
    required this.navigationShell,
    required this.location,
  });

  final StatefulNavigationShell navigationShell;
  final String location;

  Future<void> _selectBranch(
    BuildContext context,
    WidgetRef ref,
    int index,
  ) async {
    if (index == navigationShell.currentIndex) {
      if (index == 0 && location == '/feed') {
        ref.read(feedScrollToTopRequestsProvider.notifier).state++;
      }
      return;
    }
    if (ref.read(settingsHasUnsavedChangesProvider) ||
        ref.read(editProfileHasUnsavedChangesProvider)) {
      final canLeave = await confirmLeavingSettings(context, ref);
      if (!canLeave) {
        return;
      }
    }
    navigationShell.goBranch(index, initialLocation: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final hideNavigation = location.startsWith('/add/');

    return Scaffold(
      body: AuthenticatedOnboardingFlow(
        child: LostPetFollowUpListener(child: navigationShell),
      ),
      bottomNavigationBar: hideNavigation
          ? null
          : NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (index) =>
                  _selectBranch(context, ref, index),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: strings.feed,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.map_outlined),
                  selectedIcon: const Icon(Icons.map),
                  label: strings.map,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.add_circle_outline),
                  selectedIcon: const Icon(Icons.add_circle),
                  label: strings.add,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.forum_outlined),
                  selectedIcon: const Icon(Icons.forum),
                  label: strings.leaderboard,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  label: strings.profile,
                ),
              ],
            ),
    );
  }
}
