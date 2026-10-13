import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../localization/app_strings.dart';
import '../navigation/tab_actions.dart';
import '../navigation/settings_changes_guard.dart';
import '../onboarding/authenticated_onboarding_flow.dart';
import '../theme/app_design_tokens.dart';
import '../../features/lost_pets/presentation/widgets/lost_pet_follow_up_listener.dart';

/// Adaptive app shell: bottom navigation on phones, a navigation rail on
/// tablets, and an extended labelled rail on desktop browsers.
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
    final width = MediaQuery.sizeOf(context).width;
    final useRail = AppBreakpoints.isMedium(width) && !hideNavigation;
    final extended = AppBreakpoints.isExpanded(width);
    final scheme = Theme.of(context).colorScheme;

    final items = <_NavItem>[
      _NavItem(Icons.home_outlined, Icons.home_rounded, strings.feed),
      _NavItem(Icons.map_outlined, Icons.map_rounded, strings.map),
      _NavItem(Icons.add_rounded, Icons.add_rounded, strings.add,
          primary: true),
      _NavItem(Icons.emoji_events_outlined, Icons.emoji_events_rounded,
          strings.leaderboard),
      _NavItem(
          Icons.person_outline_rounded, Icons.person_rounded, strings.profile),
    ];

    final content = AuthenticatedOnboardingFlow(
      child: LostPetFollowUpListener(child: navigationShell),
    );

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                extended: extended,
                minExtendedWidth: 208,
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: (index) =>
                    _selectBranch(context, ref, index),
                labelType: extended
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pets_rounded, color: scheme.primary),
                      if (extended) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Mushukistan',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: scheme.primary,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                destinations: [
                  for (final item in items)
                    NavigationRailDestination(
                      icon: item.navIcon(context, selected: false),
                      selectedIcon: item.navIcon(context, selected: true),
                      label: Text(item.label),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: hideNavigation
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: (index) =>
                    _selectBranch(context, ref, index),
                destinations: [
                  for (final item in items)
                    NavigationDestination(
                      icon: item.navIcon(context, selected: false),
                      selectedIcon: item.navIcon(context, selected: true),
                      label: item.label,
                    ),
                ],
              ),
            ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.selectedIcon, this.label,
      {this.primary = false});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool primary;

  /// Add is the product's primary action, so it gets a filled accent badge
  /// instead of a plain glyph.
  Widget navIcon(BuildContext context, {required bool selected}) {
    if (!primary) return Icon(selected ? selectedIcon : icon);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 32,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Icon(icon, color: scheme.onPrimary, size: 26),
    );
  }
}
