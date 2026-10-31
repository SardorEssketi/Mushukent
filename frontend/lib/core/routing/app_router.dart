import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/adoption_posts/presentation/screens/adoption_post_create_screen.dart';
import '../../features/adoption_posts/presentation/screens/adoption_post_detail_screen.dart';
import '../../features/adoption_posts/presentation/screens/adoption_post_edit_screen.dart';
import '../../features/adoption_posts/presentation/screens/my_adoption_posts_screen.dart';
import '../../features/add_observation/presentation/screens/add_observation_details_screen.dart';
import '../../features/add_observation/presentation/screens/add_observation_location_screen.dart';
import '../../features/add_observation/presentation/screens/add_observation_screen.dart';
import '../../features/add_observation/application/add_observation_controller.dart';
import '../../features/auth/presentation/screens/auth_gate_screen.dart';
import '../../features/auth/presentation/screens/auth_required_screen.dart';
import '../../features/auth/presentation/screens/session_unavailable_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/verify_email_screen.dart';
import '../../features/feed/presentation/screens/feed_screen.dart';
import '../../features/leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../features/legal/presentation/screens/legal_document_screen.dart';
import '../../features/legal/presentation/screens/legal_update_screen.dart';
import '../../features/lost_pets/presentation/screens/lost_pet_create_screen.dart';
import '../../features/lost_pets/presentation/screens/lost_pet_detail_screen.dart';
import '../../features/lost_pets/presentation/screens/lost_pet_edit_screen.dart';
import '../../features/lost_pets/presentation/screens/my_lost_pets_screen.dart';
import '../../features/map/presentation/screens/map_screen.dart';
import '../../features/moderation/presentation/screens/moderation_report_detail_screen.dart';
import '../../features/moderation/presentation/screens/moderation_reports_screen.dart';
import '../../features/moderation/presentation/screens/post_history_screen.dart';
import '../../features/notifications/presentation/notification_center_screen.dart';
import '../../features/notifications/presentation/notification_settings_screen.dart';
import '../../features/moderation/presentation/screens/report_content_screen.dart';
import '../../features/posts/presentation/screens/post_detail_screen.dart';
import '../../features/posts/presentation/screens/post_edit_screen.dart';
import '../../features/profile/presentation/screens/adoption_help_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/about_account_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/public_profile_screen.dart';
import '../../features/profile/presentation/screens/feedback_screen.dart';
import '../../features/profile/presentation/screens/blocked_users_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/profile/presentation/screens/account_security_screen.dart';
import '../../features/profile/presentation/screens/user_activity_screen.dart';
import '../network/mushukistan_api.dart';
import '../navigation/settings_changes_guard.dart';
import '../startup/startup_log.dart';
import '../widgets/app_shell_scaffold.dart';
import 'auth_navigation.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _mapNavigatorKey = GlobalKey<NavigatorState>();
final _feedNavigatorKey = GlobalKey<NavigatorState>();
final _addNavigatorKey = GlobalKey<NavigatorState>();
final _leaderboardNavigatorKey = GlobalKey<NavigatorState>();
final _profileNavigatorKey = GlobalKey<NavigatorState>();

bool _isAuthenticationEntryRoute(String path) =>
    path == '/login' || path == '/register' || path == '/auth-required';

/// Where protected routes go while a stored session could not be confirmed (server unreachable).
/// Deliberately not the sign-in flow: the user is still signed in as far as we know.
String sessionUnavailableLocation(Uri intendedLocation) {
  final redirect =
      validatedPostAuthRedirect(intendedLocation.toString()) ?? '/feed';
  return Uri(
    path: '/session-unavailable',
    queryParameters: {'redirect': redirect},
  ).toString();
}

/// The route the user is looking at. The router's own URI only knows the declarative location; a
/// screen opened with `context.push` (the Feed's Login button) is the last match of the delegate's
/// configuration instead.
Uri visibleRouteUri(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  final declared = router.routeInformationProvider.value.uri;
  if (configuration.isEmpty) return declared;
  final visiblePath = configuration.last.matchedLocation;
  return visiblePath == declared.path ? declared : Uri(path: visiblePath);
}

/// Pages owned by the sign-in, session and legal redirects. A notification never stacks on top of
/// them: the redirects decide where the user goes next.
const _gateLocations = <String>{
  '/auth-gate',
  '/auth-required',
  '/session-unavailable',
  '/legal-update',
  '/login',
  '/register',
  '/verify-email',
};

/// Opens [destination] (a notification target, optionally with a query) so Back has somewhere
/// sensible to go: it is pushed on top of the screen the user is on, and a cold start is on the
/// Feed, so Back leads there. A destination that is already on screen is not opened twice.
void openNotificationDestination(GoRouter router, String destination) {
  final target = Uri.parse(destination);
  final visible = visibleRouteUri(router);
  if (visible.path == target.path) return;
  if (_gateLocations.contains(visible.path)) {
    router.go(destination);
    return;
  }
  unawaited(router.push<void>(destination));
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final location = state.uri.path;

      if (location == '/' || location == '/auth-gate') {
        return '/feed';
      }

      // Outdated legal acceptance: documents, the acceptance screen and logout stay reachable;
      // everything else waits for an explicit acceptance. Evaluated per signed-in account.
      final legalPending = authState.isAuthenticated &&
          authState.user?.legalAcceptanceRequired == true;
      if (legalPending) {
        if (location == '/legal-update' || location.startsWith('/legal/')) {
          return null;
        }
        return Uri(
          path: '/legal-update',
          queryParameters: {
            'redirect':
                validatedPostAuthRedirect(state.uri.toString()) ?? '/feed',
          },
        ).toString();
      }
      if (location == '/legal-update') {
        return validatedPostAuthRedirect(
                state.uri.queryParameters['redirect']) ??
            '/feed';
      }

      final isAuthEntryRoute = _isAuthenticationEntryRoute(location);
      final isModeratorRoute = location.startsWith('/moderation');
      final isProtectedRoute = location.startsWith('/add') ||
          location.startsWith('/profile') ||
          location.startsWith('/notifications') ||
          location == '/report' ||
          ((location.startsWith('/posts/') ||
                  location.startsWith('/lost-pets/') ||
                  location.startsWith('/adoption-posts/')) &&
              location.endsWith('/edit'));

      if (location == '/auth-required' &&
          authState.phase == AuthPhase.sessionUnavailable) {
        // A cold load of a protected URL parks on /auth-required while the session is being
        // checked; once the check ends as "server unreachable" this is not a sign-in problem.
        return sessionUnavailableLocation(
          Uri.parse(
            validatedPostAuthRedirect(state.uri.queryParameters['redirect']) ??
                '/feed',
          ),
        );
      }

      if (location == '/session-unavailable' &&
          authState.phase != AuthPhase.sessionUnavailable) {
        // Recovered (or the session was confirmed gone): continue to where the user was going.
        return validatedPostAuthRedirect(
                state.uri.queryParameters['redirect']) ??
            '/feed';
      }

      if ((isModeratorRoute || isProtectedRoute) &&
          authState.phase == AuthPhase.sessionUnavailable) {
        return sessionUnavailableLocation(state.uri);
      }

      if (isModeratorRoute) {
        if (!authState.isAuthenticated) {
          return authenticationRequiredLocation(state.uri);
        }
        if (authState.user?.isModerator != true) {
          return '/profile';
        }
        return null;
      }

      if (isProtectedRoute && !authState.isAuthenticated) {
        if (authState.phase == AuthPhase.verificationRequired) {
          return '/verify-email';
        }
        return authenticationRequiredLocation(state.uri);
      }

      switch (authState.phase) {
        case AuthPhase.initial:
        case AuthPhase.restoring:
        case AuthPhase.sessionUnavailable:
        case AuthPhase.failure:
        case AuthPhase.unauthenticated:
        case AuthPhase.authenticating:
          return null;
        case AuthPhase.verificationRequired:
          if (isAuthEntryRoute) {
            return '/verify-email';
          }
          return null;
        case AuthPhase.authenticated:
          if (isAuthEntryRoute || location == '/verify-email') {
            return validatedPostAuthRedirect(
                  state.uri.queryParameters['redirect'],
                ) ??
                '/feed';
          }
          return null;
      }
    },
    errorBuilder: (context, state) {
      return const Scaffold(
        body: Center(child: Text('This page is not available.')),
      );
    },
    routes: [
      GoRoute(
        path: '/auth-gate',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AuthGateScreen(),
      ),
      // The pages below are where redirects park a route while the session is being decided, so
      // they replace the app shell and the shell comes back as soon as the answer arrives. They
      // appear without a transition: an animated one keeps the replaced shell route mounted until
      // it ends, and a shell re-added within that window would be a second owner of the shell's
      // GlobalKey (Duplicate GlobalKey).
      GoRoute(
        path: '/legal-update',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const LegalUpdateScreen(),
        ),
      ),
      GoRoute(
        path: '/session-unavailable',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const SessionUnavailableScreen(),
        ),
      ),
      GoRoute(
        path: '/auth-required',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: AuthRequiredScreen(
            redirect: validatedPostAuthRedirect(
              state.uri.queryParameters['redirect'],
            ),
          ),
        ),
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
          return AppShellScaffold(
            navigationShell: navigationShell,
            location: state.uri.path,
          );
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
                  return MapScreen(
                    focusLocation: focusLocation,
                    focusLostPetId: state.uri.queryParameters['lostPetId'],
                    focusNeedsHelp:
                        state.uri.queryParameters['focus'] == 'needs_help',
                  );
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
                        const AddObservationDetailsScreen(),
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
                    redirect: (context, state) => '/feed',
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
                    path: 'lost-pets',
                    builder: (context, state) => const MyLostPetsScreen(),
                  ),
                  GoRoute(
                    path: 'adoption-posts',
                    builder: (context, state) => const MyAdoptionPostsScreen(),
                  ),
                  GoRoute(
                    path: 'feedback',
                    builder: (context, state) => const FeedbackScreen(),
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                    routes: [
                      GoRoute(
                        path: 'security',
                        builder: (context, state) =>
                            const AccountSecurityScreen(),
                      ),
                      GoRoute(
                        path: 'notifications',
                        builder: (context, state) =>
                            const NotificationSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'blocked-users',
                        builder: (context, state) => const BlockedUsersScreen(),
                      ),
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
        path: '/notifications',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationCenterScreen(),
        routes: [
          GoRoute(
            path: 'settings',
            redirect: (context, state) => '/profile/settings/notifications',
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
        builder: (context, state) => PostDetailScreen(
          postId: state.pathParameters['postId'] ?? '',
          focusComments: state.uri.queryParameters['comments'] == '1',
        ),
      ),
      GoRoute(
        path: '/posts/:postId/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            PostEditScreen(postId: state.pathParameters['postId'] ?? ''),
      ),
      GoRoute(
        path: '/lost-pets/:lostPetId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => LostPetDetailScreen(
          lostPetId: state.pathParameters['lostPetId'] ?? '',
          focusComments: state.uri.queryParameters['comments'] == '1',
        ),
      ),
      GoRoute(
        path: '/lost-pets/:lostPetId/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => LostPetEditScreen(
          lostPetId: state.pathParameters['lostPetId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/adoption-posts/:adoptionPostId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => AdoptionPostDetailScreen(
          adoptionPostId: state.pathParameters['adoptionPostId'] ?? '',
          focusComments: state.uri.queryParameters['comments'] == '1',
        ),
      ),
      GoRoute(
        path: '/adoption-posts/:adoptionPostId/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => AdoptionPostEditScreen(
          adoptionPostId: state.pathParameters['adoptionPostId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/report',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ReportContentScreen(
          initialTargetType: state.uri.queryParameters['type'],
          initialTargetId: state.uri.queryParameters['id'],
          initialTargetLabel: state.uri.queryParameters['label'],
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
      GoRoute(
        path: '/moderation/posts/:postId/history',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            PostHistoryScreen(postId: state.pathParameters['postId'] ?? ''),
      ),
    ],
  );

  logStartupStage('Router ready');

  ref.listen<AuthState>(authControllerProvider, (previous, authState) {
    if (previous?.user?.id != authState.user?.id) {
      ref.read(editProfileHasUnsavedChangesProvider.notifier).state = false;
      ref.invalidate(profileMeProvider);
      ref.invalidate(feedPostsProvider);
      ref.invalidate(postLikeOverridesProvider);
      ref.invalidate(addObservationControllerProvider);
      ref.invalidate(lostPetMutationOverridesProvider);
      ref.invalidate(deletedLostPetIdsProvider);
      ref.invalidate(resolvedLostPetIdsProvider);
      ref.invalidate(adoptionMutationOverridesProvider);
      ref.invalidate(deletedAdoptionIdsProvider);
      ref.invalidate(resolvedAdoptionIdsProvider);
    }
    if (previous?.isAuthenticated == true &&
        (authState.phase == AuthPhase.unauthenticated ||
            authState.phase == AuthPhase.failure)) {
      router.go('/feed');
      return;
    }
    // The router's URI only knows the declarative location. A screen opened with `context.push`
    // (the Feed's Login button) is not part of it, so the visible route is the last match of the
    // delegate's configuration, which includes pushed pages.
    final currentUri = visibleRouteUri(router);
    final isAuthEntryRoute = _isAuthenticationEntryRoute(currentUri.path) ||
        currentUri.path == '/verify-email';

    if (authState.isAuthenticated && isAuthEntryRoute) {
      final destination = validatedPostAuthRedirect(
        currentUri.queryParameters['redirect'],
      );
      router.go(destination ?? '/feed');
      return;
    }

    router.refresh();
  });
  ref.onDispose(router.dispose);
  return router;
});
