import 'package:flutter/material.dart';

import '../widgets/ocean_background.dart';
import 'auth_service.dart';

/// Combined sign-in / sign-up screen.
///
/// One screen with a mode toggle rather than two routes: the fields are almost
/// identical and it keeps whatever the user already typed when they realise
/// they meant to do the other one.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

enum _AuthMode { login, signUp }

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();
  final TextEditingController _displayName = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _isBusy = false;
  bool _obscurePassword = true;
  String? _error;
  String? _notice;

  bool get _isSignUp => _mode == _AuthMode.signUp;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _displayName.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _mode = _isSignUp ? _AuthMode.login : _AuthMode.signUp;
      _error = null;
      _notice = null;
      _confirmPassword.clear();
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
      _notice = null;
    });

    try {
      if (_isSignUp) {
        await widget.authService.signUp(
          email: _email.text,
          password: _password.text,
          displayName: _displayName.text,
        );
      } else {
        await widget.authService.signIn(
          email: _email.text,
          password: _password.text,
        );
      }
      // On success AuthGate swaps this page out; no navigation needed here.
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Unexpected error: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _resetPassword() async {
    final String email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email first, then tap reset.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
      _notice = null;
    });

    try {
      await widget.authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(() => _notice = 'Password reset email sent to $email.');
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String? _validateEmail(String? value) {
    final String email = (value ?? '').trim();
    if (email.isEmpty) return 'Email is required.';
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'Password is required.';
    // Firebase itself rejects anything shorter, so catch it before the request.
    if (_isSignUp && password.length < 6) {
      return 'Use at least 6 characters.';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_isSignUp) return null;
    if (value != _password.text) return 'Passwords do not match.';
    return null;
  }

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildCard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FCFF),
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF003049).withValues(alpha: 0.25),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Center(child: DuckSuitCapybara(size: 76)),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Ocean Lists',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF005F8F),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                _isSignUp
                    ? 'Create an account to save your tasks.'
                    : 'Welcome back. Log in to see your tasks.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF41708A),
                ),
              ),
            ),
            const SizedBox(height: 22),
            if (_isSignUp) ...<Widget>[
              TextFormField(
                controller: _displayName,
                enabled: !_isBusy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name (optional)',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _email,
              enabled: !_isBusy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: _validateEmail,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              enabled: !_isBusy,
              obscureText: _obscurePassword,
              validator: _validatePassword,
              textInputAction: _isSignUp
                  ? TextInputAction.next
                  : TextInputAction.done,
              onFieldSubmitted: (_) => _isSignUp ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(
                    () => _obscurePassword = !_obscurePassword,
                  ),
                ),
              ),
            ),
            if (_isSignUp) ...<Widget>[
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmPassword,
                enabled: !_isBusy,
                obscureText: _obscurePassword,
                validator: _validateConfirmPassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 16),
              _buildBanner(
                _error!,
                const Color(0xFFB3261E),
                Icons.error_outline,
              ),
            ],
            if (_notice != null) ...<Widget>[
              const SizedBox(height: 16),
              _buildBanner(
                _notice!,
                const Color(0xFF0077B6),
                Icons.mark_email_read_outlined,
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _isBusy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0077B6),
                ),
                child: _isBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isSignUp ? 'Create account' : 'Log in',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            if (!_isSignUp)
              TextButton(
                onPressed: _isBusy ? null : _resetPassword,
                child: const Text('Forgot password?'),
              ),
            const SizedBox(height: 4),
            // Wrap, not Row: on a narrow phone the label plus button is wider
            // than the card and a Row would overflow instead of stacking.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  _isSignUp
                      ? 'Already have an account?'
                      : "Don't have an account?",
                  style: const TextStyle(color: Color(0xFF41708A)),
                ),
                TextButton(
                  onPressed: _isBusy ? null : _toggleMode,
                  child: Text(_isSignUp ? 'Log in' : 'Sign up'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner(String message, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
