import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/pages/bib_search_page.dart';
import 'package:rsu_results/pages/bootstrap_page.dart';
import 'package:rsu_results/pages/date_range_page.dart';
import 'package:rsu_results/pages/global_oauth_settings_page.dart';
import 'package:rsu_results/pages/login_page.dart';
import 'package:rsu_results/pages/oauth_callback_page.dart';
import 'package:rsu_results/pages/oauth_waiting_page.dart';
import 'package:rsu_results/pages/race_picker_page.dart';
import 'package:rsu_results/pages/race_settings_page.dart';
import 'package:rsu_results/pages/results_page.dart';
import 'package:rsu_results/rsu/app_state.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.bootstrap,
    redirect: (context, state) {
      // Web note: Dreamflow uses hash-based routing (e.g. `#/login`). Some OAuth providers (including
      // RunSignup) redirect to the site root with query params BEFORE the hash:
      //   https://domain/?code=...&state=...#/login
      // In that situation, `state.uri.queryParameters` will be empty because the router only sees
      // the hash fragment. So we also consult `Uri.base.queryParameters` on web.

      final stateQp = state.uri.queryParameters;
      final baseQp = kIsWeb ? Uri.base.queryParameters : const <String, String>{};

      bool hasOauthParams(Map<String, String> qp) => qp.containsKey('code') || qp.containsKey('error') || qp.containsKey('state');

      final effectiveQp = hasOauthParams(stateQp) ? stateQp : (hasOauthParams(baseQp) ? baseQp : const <String, String>{});

      // If we have OAuth params and we’re not already on the callback page, forward internally to it.
      // We intentionally do this regardless of the current hash route (login, bootstrap, etc.).
      if (effectiveQp.isNotEmpty && state.uri.path != AppRoutes.oauthCallback) {
        final q = Uri(queryParameters: effectiveQp).query;
        return q.isEmpty ? AppRoutes.oauthCallback : '${AppRoutes.oauthCallback}?$q';
      }

      // Lock navigation once the user has progressed into the race search flow.
      // Requirement: after reaching the results search page, users should not be able to go “back”
      // to date/race selection nor access settings.
      try {
        final app = context.read<RsuAppState>();
        final hasToken = (app.accessToken ?? '').trim().isNotEmpty;
        final raceId = (app.raceId ?? '').trim();
        final locked = hasToken && raceId.isNotEmpty;

        if (locked) {
          final path = state.uri.path;
          final allowed = path == AppRoutes.search || path == AppRoutes.results || path == AppRoutes.oauthCallback || path == AppRoutes.oauthWaiting;

          if (!allowed || path == AppRoutes.settingsGlobal || path == AppRoutes.settingsRace || path == AppRoutes.dates || path == AppRoutes.races || path == AppRoutes.login || path == AppRoutes.bootstrap) {
            // Always keep them in the search flow.
            return '${AppRoutes.search}?raceId=$raceId';
          }

          // Sanitize missing raceId in query params so deep links stay consistent.
          if ((path == AppRoutes.search || path == AppRoutes.results) && (state.uri.queryParameters['raceId'] ?? '').trim().isEmpty) {
            final qp = Map<String, String>.from(state.uri.queryParameters);
            qp['raceId'] = raceId;
            final q = Uri(queryParameters: qp).query;
            return '${path}?$q';
          }
        }
      } catch (e) {
        // If the provider isn’t available yet, ignore and continue.
        debugPrint('Router redirect appState read failed (ignored): $e');
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.bootstrap,
        name: 'bootstrap',
        pageBuilder: (context, state) => const NoTransitionPage(child: BootstrapPage()),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        pageBuilder: (context, state) => const NoTransitionPage(child: LoginPage()),
      ),
      GoRoute(
        path: AppRoutes.oauthWaiting,
        name: 'oauth_waiting',
        pageBuilder: (context, state) {
          final expectedState = state.uri.queryParameters['state'] ?? '';
          return NoTransitionPage(child: OAuthWaitingPage(state: expectedState));
        },
      ),
      GoRoute(
        path: AppRoutes.oauthCallback,
        name: 'oauth_callback',
        pageBuilder: (context, state) {
          final code = state.uri.queryParameters['code'] ?? '';
          final returnedState = state.uri.queryParameters['state'] ?? '';
          return NoTransitionPage(child: OAuthCallbackPage(code: code, returnedState: returnedState));
        },
      ),
      GoRoute(
        path: AppRoutes.dates,
        name: 'dates',
        pageBuilder: (context, state) => const NoTransitionPage(child: DateRangePage()),
      ),
      GoRoute(
        path: AppRoutes.races,
        name: 'races',
        pageBuilder: (context, state) => const NoTransitionPage(child: RacePickerPage()),
      ),
      GoRoute(
        path: AppRoutes.search,
        name: 'search',
        pageBuilder: (context, state) {
          final raceId = state.uri.queryParameters['raceId'] ?? '';
          return NoTransitionPage(child: BibSearchPage(raceId: raceId));
        },
      ),
      GoRoute(
        path: AppRoutes.results,
        name: 'results',
        pageBuilder: (context, state) {
          final raceId = state.uri.queryParameters['raceId'] ?? '';
          final searchType = state.uri.queryParameters['searchType'] ?? 'bib';
          final bib = state.uri.queryParameters['bib'];
          final name = state.uri.queryParameters['name'];
          return NoTransitionPage(child: ResultsPage(raceId: raceId, searchType: searchType, bib: bib, name: name));
        },
      ),
      GoRoute(
        path: AppRoutes.settingsGlobal,
        name: 'settings_global',
        pageBuilder: (context, state) => const NoTransitionPage(child: GlobalOAuthSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsRace,
        name: 'settings_race',
        pageBuilder: (context, state) {
          final raceId = state.uri.queryParameters['raceId'] ?? '';
          return NoTransitionPage(child: RaceSettingsPage(raceId: raceId));
        },
      ),
    ],
  );
}

class AppRoutes {
  static const String bootstrap = '/';
  static const String login = '/login';

  static const String oauthWaiting = '/oauth/waiting';
  static const String oauthCallback = '/oauth/callback';

  static const String dates = '/dates';
  static const String races = '/races';
  static const String search = '/search';
  static const String results = '/results';

  static const String settingsGlobal = '/settings/oauth';
  static const String settingsRace = '/settings/race';
}
