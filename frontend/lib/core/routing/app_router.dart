import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/adoption_posts/presentation/screens/adoption_post_create_screen.dart';
import '../../features/adoption_posts/presentation/screens/adoption_post_detail_screen.dart';
import '../../features/add_observation/presentation/screens/add_observation_details_screen.dart';
import '../../features/add_observation/presentation/screens/add_observation_entry_screen.dart';
import '../../features/add_observation/presentation/screens/add_observation_location_screen.dart';
import '../../features/add_observation/presentation/screens/add_observation_screen.dart';
import '../../features/add_observation/presentation/screens/publish_success_screen.dart';
import '../../features/auth/presentation/screens/auth_gate_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/verify_email_screen.dart';
import '../../features/feed/presentation/screens/feed_screen.dart';
import '../../features/leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../features/legal/presentation/screens/legal_document_screen.dart';
import '../../features/lost_pets/presentation/screens/lost_pet_create_screen.dart';
import '../../features/lost_pets/presentation/screens/lost_pet_detail_screen.dart';
import '../../features/map/presentation/screens/map_screen.dart';
import '../../features/moderation/presentation/screens/moderation_report_detail_screen.dart';
import '../../features/moderation/presentation/screens/moderation_reports_screen.dart';
import '../../features/moderation/presentation/screens/report_content_screen.dart';
import '../../features/posts/presentation/screens/post_detail_screen.dart';
import '../../features/profile/presentation/screens/adoption_help_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/about_account_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/public_profile_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/profile/presentation/screens/user_activity_screen.dart';
import '../network/mushukistan_api.dart';
import '../widgets/app_shell_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _mapNavigatorKey = GlobalKey<NavigatorState>();
final _feedNavigatorKey = GlobalKey<NavigatorState>();
final _addNavigatorKey = GlobalKey<NavigatorState>();
final _leaderboardNavigatorKey = GlobalKey<NavigatorState>();
final _profileNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final location = state.uri.path;

      if (location == '/') {
        return '/auth-gate';
      }

      final isAuthRoute = location == '/auth-gate' ||
          location == '/login' ||
          location == '/register' ||
          location == '/verify-email';
      final isProtectedRoute = location == '/map' ||
          location.startsWith('/feed') ||
          location.startsWith('/add') ||
          location.startsWith('/leaderboards') ||
          location.startsWith('/profile') ||
          location.startsWith('/report') ||
          location.startsWith('/moderation');

      switch (authState.phase) {
        case AuthPhase.initial:
        case AuthPhase.restoring:
          return location == '/auth-gate' || location == '/verify-email'
              ? null
              : '/auth-gate';
        case AuthPhase.failure:
          if (isProtectedRoute) {
            return '/auth-gate';
          }
          return null;
        case AuthPhase.unauthenticated:
          if (location == '/auth-gate') {
            return '/login';
          }
          if (isProtectedRoute) {
            return '/login';
          }
          return null;
        case AuthPhase.verificationRequired:
          if (location == '/auth-gate' ||
              location == '/login' ||
              location == '/register') {
            return '/verify-email';
          }
          if (isProtectedRoute) {
            return '/verify-email';
          }
          return null;
        case AuthPhase.authenticating:
          return null;
        case AuthPhase.authenticated:
          if (isAuthRoute) {
            return '/feed';
          }
          return null;
      }
    },
    errorBuilder: (context, state) {
      return Scaffold(
        body: Center(
          child: Text(state.error?.toString() ?? 'Route not found.'),
        ),
      );
    },
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
      GoRoute(
        path: '/legal/terms',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LegalDocumentScreen(
          documentType: LegalDocumentType.termsOfService,
        ),
      ),
      GoRoute(
        path: '/legal/privacy',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LegalDocumentScreen(
          documentType: LegalDocumentType.privacyPolicy,
        ),
      ),
      GoRoute(
        path: '/verify-email',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => VerifyEmailScreen(
          token: state.uri.queryParameters['token'],
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShellScaffold(navigationShell: navigationShell);
        },
        branches: [
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
            navigatorKey: _mapNavigatorKey,
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) {
                  final latitude = double.tryParse(
                    state.uri.queryParameters['lat'] ?? '',
                  );
                  final longitude = double.tryParse(
                    state.uri.queryParameters['lon'] ?? '',
                  );
                  final focusLocation = latitude == null || longitude == null
                      ? null
                      : GeoPoint(latitude: latitude, longitude: longitude);
                  return MapScreen(focusLocation: focusLocation);
                },
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
                    builder: (context, state) =>
                        const AddObservationEntryScreen(),
                  ),
                  GoRoute(
                    path: 'details',
                    builder: (context, state) =>
                        const AddObservationDetailsScreen(),
                  ),
                  GoRoute(
                    path: 'location',
                    builder: (context, state) =>
                        const AddObservationLocationScreen(),
                  ),
                  GoRoute(
                    path: 'lost-pet',
                    builder: (context, state) => const LostPetCreateScreen(),
                  ),
                  GoRoute(
                    path: 'adoption',
                    builder: (context, state) =>
                        const AdoptionPostCreateScreen(),
                  ),
                  GoRoute(
                    path: 'success',
                    builder: (context, state) =>
                        PublishSuccessScreen(post: state.extra as PostDetail?),
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
                  GoRoute(
                    path: 'adoption-help',
                    builder: (context, state) => const AdoptionHelpScreen(),
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                    routes: [
                      GoRoute(
                        path: 'about-account',
                        builder: (context, state) => const AboutAccountScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'observations',
                    builder: (context, state) {
                      final user = ref.read(currentUserProvider);
                      return UserPostsScreen(
                        userId: user?.id ?? '',
                        isCurrentUser: true,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'comments',
                    builder: (context, state) {
                      final user = ref.read(currentUserProvider);
                      return UserCommentsScreen(
                        userId: user?.id ?? '',
                        isCurrentUser: true,
                      );
                    },
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
          return PublicProfileScreen(
              userId: state.pathParameters['userId'] ?? '');
        },
      ),
      GoRoute(
        path: '/users/:userId/observations',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          return UserPostsScreen(
            userId: state.pathParameters['userId'] ?? '',
            isCurrentUser: false,
          );
        },
      ),
      GoRoute(
        path: '/users/:userId/comments',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          return UserCommentsScreen(
            userId: state.pathParameters['userId'] ?? '',
            isCurrentUser: false,
          );
        },
      ),
      GoRoute(
        path: '/posts/:postId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            PostDetailScreen(postId: state.pathParameters['postId'] ?? ''),
      ),
      GoRoute(
        path: '/lost-pets/:lostPetId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => LostPetDetailScreen(
          lostPetId: state.pathParameters['lostPetId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/adoption-posts/:adoptionPostId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => AdoptionPostDetailScreen(
          adoptionPostId: state.pathParameters['adoptionPostId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/report',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ReportContentScreen(
          initialTargetType: state.uri.queryParameters['type'],
          initialTargetId: state.uri.queryParameters['id'],
        ),
      ),
      GoRoute(
        path: '/moderation/reports',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ModerationReportsScreen(),
      ),
      GoRoute(
        path: '/moderation/reports/:reportId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ModerationReportDetailScreen(
          reportId: state.pathParameters['reportId'] ?? '',
        ),
      ),
    ],
  );

  ref.listen<AuthState>(authControllerProvider, (_, __) {
    router.refresh();
  });
  ref.onDispose(router.dispose);
  return router;
});
