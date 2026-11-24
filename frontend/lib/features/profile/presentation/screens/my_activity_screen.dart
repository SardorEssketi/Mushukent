import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../adoption_posts/presentation/screens/my_adoption_posts_screen.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../lost_pets/presentation/screens/my_lost_pets_screen.dart';
import 'user_activity_screen.dart';

/// The tabs of [MyActivityScreen], in order. [query] is the `?tab=` value of
/// `/profile/activity`.
enum MyActivityTab {
  cats('cats'),
  needsHelp('needs-help'),
  lostPets('lost-pets'),
  rehoming('rehoming');

  const MyActivityTab(this.query);

  final String query;

  String get location => '/profile/activity?tab=$query';

  /// Unknown or missing values open the first tab.
  static MyActivityTab fromQuery(String? value) => MyActivityTab.values
      .firstWhere((tab) => tab.query == value, orElse: () => cats);

  String label(AppStrings strings) => switch (this) {
        cats => strings.activityTabCats,
        needsHelp => strings.activityTabNeedsHelp,
        lostPets => strings.activityTabLostPets,
        rehoming => strings.activityTabRehoming,
      };
}

/// "Your activities": the user's own cat posts, needs-help posts, lost-pet
/// reports and rehoming posts, one tab each. Each tab is the same list the
/// old separate screens showed; a tab is built (and loads) only when first
/// opened and then stays alive, keeping its scroll position.
class MyActivityScreen extends ConsumerStatefulWidget {
  const MyActivityScreen({super.key, this.initialTab = MyActivityTab.cats});

  final MyActivityTab initialTab;

  @override
  ConsumerState<MyActivityScreen> createState() => _MyActivityScreenState();
}

class _MyActivityScreenState extends ConsumerState<MyActivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: MyActivityTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _list(MyActivityTab tab, String userId) => switch (tab) {
        MyActivityTab.cats => UserPostsScreen(
            userId: userId,
            isCurrentUser: true,
            kind: 'observation',
            embedded: true,
          ),
        MyActivityTab.needsHelp => UserPostsScreen(
            userId: userId,
            isCurrentUser: true,
            kind: 'needs_help',
            embedded: true,
          ),
        MyActivityTab.lostPets => const MyLostPetsScreen(embedded: true),
        MyActivityTab.rehoming => const MyAdoptionPostsScreen(embedded: true),
      };

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final userId = ref.watch(currentUserProvider)?.id ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.yourActivities),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final tab in MyActivityTab.values)
              Tab(
                key: ValueKey('my-activity-tab-${tab.query}'),
                text: tab.label(strings),
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final tab in MyActivityTab.values)
            _KeepAlive(
              key: ValueKey('my-activity-page-${tab.query}'),
              child: _list(tab, userId),
            ),
        ],
      ),
    );
  }
}

/// Keeps a tab's list (state, loaded pages, scroll position) once built.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
