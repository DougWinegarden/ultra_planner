import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../main.dart' show OceanListsPage;
import '../widgets/ocean_background.dart';
import 'auth_service.dart';
import 'login_page.dart';

/// Decides which screen the app opens on: the setup notice, the login page, or
/// the planner itself.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.startupError});

  /// Message from a failed `Firebase.initializeApp`, if it failed.
  final String? startupError;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Lazy on purpose: constructing this touches `FirebaseAuth.instance`, which
  /// throws if `Firebase.initializeApp` never ran. The checks in [build] have to
  /// be able to run and render the setup screen before that happens.
  late final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    if (widget.startupError != null) {
      return SetupNoticeScreen(
        title: 'Firebase could not start',
        message: widget.startupError!,
      );
    }

    if (!DefaultFirebaseOptions.isConfigured) {
      return const SetupNoticeScreen(
        title: 'Firebase is not configured yet',
        message:
            'lib/firebase_options.dart still contains placeholder values.\n\n'
            'Sign in to the Firebase project, run "flutterfire configure" to '
            'regenerate that file, then restart the app.\n\n'
            'Step-by-step instructions are in FIREBASE_SETUP.md.',
      );
    }

    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _OceanLoadingScreen(label: 'Checking your account...');
        }

        final User? user = snapshot.data;
        if (user == null) {
          return LoginPage(authService: _authService);
        }

        // Keyed by uid so switching accounts rebuilds the planner from scratch
        // rather than reusing the previous user's state.
        return OceanListsPage(
          key: ValueKey<String>(user.uid),
          user: user,
          authService: _authService,
        );
      },
    );
  }
}

class _OceanLoadingScreen extends StatelessWidget {
  const _OceanLoadingScreen({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: AnimatedOceanBackground()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const DuckSuitCapybara(size: 84),
                const SizedBox(height: 18),
                const CircularProgressIndicator(color: Color(0xFF0077B6)),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF005F8F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen explanation shown when the app cannot reach Firebase at all.
class SetupNoticeScreen extends StatelessWidget {
  const SetupNoticeScreen({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: AnimatedOceanBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4FCFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.settings_suggest_outlined,
                              color: Color(0xFF0077B6),
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF005F8F),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          message,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Color(0xFF33607A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
