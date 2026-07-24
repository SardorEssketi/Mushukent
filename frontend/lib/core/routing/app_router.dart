import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/add_observation/presentation/screens/add_observation_details_screen.dart';
import '../../features/add_observation/presentation/screens/add_observation_entry_screen.dart';
import '../../features/add_observation/presentation/screens/add_observation_screen.dart';
import '../../features/add_observation/presentation/screens/publish_success_screen.dart';
import '../../features/auth/presentation/screens/auth_gate_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/cats/presentation/screens/cat_detail_screen.dart';
import '../../features/comments/presentation/screens/comments_screen.dart';
import '../../features/feed/presentation/screens/feed_screen.dart';
import '../../features/leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../features/map/presentation/screens/map_screen.dart';
import '../../features/moderation/presentation/screens/moderation_report_detail_screen.dart';
import '../../features/moderation/presentation/screens/moderation_reports_screen.dart';
import '../../features/moderation/presentation/screens/report_content_screen.dart';
import '../../features/posts/presentation/screens/post_detail_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/public_profile_screen.dart';
import '../widgets/app_shell_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _mapNavigatorKey = GlobalKey<NavigatorState>();
final _feedNavigatorKey = GlobalKey<NavigatorState>();
final _addNavigatorKey = GlobalKey<NavigatorState>();
final _leaderboardNavigatorKey = GlobalKey<NavigatorState>();
final _profileNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/auth-gate',
    routes: [
      GoRoute(
        path: '/auth-gate',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AuthGateScreen(),
      ),
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _mapNavigatorKey,
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _feedNavigatorKey,
            routes: [
              GoRoute(
                path: '/feed',
                builder: (context, state) => const FeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _addNavigatorKey,
            routes: [
              GoRoute(
                path: '/add',
                builder: (context, state) => const AddObservationScreen(),
                routes: [
                  GoRoute(
                    path: 'entry',
                    builder: (context, state) => const AddObservationEntryScreen(),
                  ),
                  GoRoute(
                    path: 'details',
                    builder: (context, state) => const AddObservationDetailsScreen(),
                  ),
                  GoRoute(
                    path: 'success',
                    builder: (context, state) => const PublishSuccessScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _leaderboardNavigatorKey,
            routes: [
              GoRoute(
                path: '/leaderboards',
                builder: (context, state) => const LeaderboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileNavigatorKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/users/:userId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          return PublicProfileScreen(userId: state.pathParameters['userId'] ?? '');
        },
      ),
      GoRoute(
        path: '/cats/:catId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => CatDetailScreen(catId: state.pathParameters['catId'] ?? ''),
      ),
      GoRoute(
        path: '/posts/:postId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => PostDetailScreen(postId: state.pathParameters['postId'] ?? ''),
      ),
      GoRoute(
        path: '/posts/:postId/comments',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => CommentsScreen(postId: state.pathParameters['postId'] ?? ''),
      ),
      GoRoute(
        path: '/report',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ReportContentScreen(),
      ),
      GoRoute(
        path: '/moderation/reports',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ModerationReportsScreen(),
      ),
      GoRoute(
        path: '/moderation/reports/:reportId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ModerationReportDetailScreen(),
      ),
    ],
  );
});
