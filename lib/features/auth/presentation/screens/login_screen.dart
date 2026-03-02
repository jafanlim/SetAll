import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/auth_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/biometric_service.dart';

/// Login / sign-up screen: Email (with password) and Google.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocus    = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isSignUp = false;
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    _message = null;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (_isSignUp) {
        final redirectUrl = _authRedirectUrl();
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: redirectUrl,
        );
        if (mounted) {
          setState(() {
            _loading = false;
            _message = 'Check your email to confirm your account, then sign in.';
          });
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
        if (mounted) {
          final bio = BiometricService.instance;
                      final canUse = await bio.canUseBiometrics();
                      if (!mounted) return;
                      if (canUse) {
                        final useBio = await showDialog<bool>(
                          context: context,
          
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Use Face ID to unlock?'),
                content: const Text(
                  'Next time you open the app, you can unlock with Face ID instead of entering your password.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Not now'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Enable'),
                  ),
                ],
              ),
            );
            if (useBio == true) await bio.setUseBiometric(true);
          }
          if (mounted) context.go(AppRouter.dashboard);
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = e.toString();
        });
      }
    }
  }

  /// Base URL for email/OAuth redirects so confirmation and Google redirect work on mobile (e.g. open link on iPhone).
  String? _authRedirectUrl() {
    if (kAuthRedirectBaseUrl.isNotEmpty) {
      // Custom scheme deep links (e.g. com.jafa.setall://login-callback) must
      // not have a trailing slash added — return them verbatim.
      if (!kAuthRedirectBaseUrl.startsWith('http')) {
        return kAuthRedirectBaseUrl;
      }
      return kAuthRedirectBaseUrl.endsWith('/') ? kAuthRedirectBaseUrl : '$kAuthRedirectBaseUrl/';
    }
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return origin.endsWith('/') ? origin : '$origin/';
    }
    return null;
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _message = 'Enter your email above, then tap “Forgot password”.');
      return;
    }
    setState(() { _loading = true; _message = null; });
    try {
      final redirectUrl = _authRedirectUrl();
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectUrl,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Password reset email sent to $email. Check your inbox.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() { _loading = false; _message = e.message; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _message = e.toString(); });
    }
  }

  Future<void> _signInWithGoogle() async {
    _message = null;
    setState(() => _loading = true);
    try {
      final redirectUrl = _authRedirectUrl();
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        authScreenLaunchMode: LaunchMode.platformDefault,
        queryParams: const {'prompt': 'select_account'},
      );
      if (mounted) setState(() => _loading = false);
      // Web: redirect happens in browser; app will reload with session.
      // Mobile: may return here after in-app browser.
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = _friendlyAuthMessage(e.message);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = _friendlyAuthMessage(e.toString());
        });
      }
    }
  }

  String _friendlyAuthMessage(String raw) {
    if (raw.contains('not enabled') || raw.contains('Unsupported provider') || raw.contains('provider is not enabled')) {
      return 'Google sign-in is not enabled. In Supabase dashboard go to Authentication → Providers → Google, enable it, and add your Google Client ID and Secret.';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'SetAll',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSignUp ? 'Create an account' : 'Sign in to continue',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter your email';
                        if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      obscureText: true,
                      autofillHints: _isSignUp
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submitEmail(),
                      decoration: InputDecoration(
                        labelText: _isSignUp ? 'Password (min 6 characters)' : 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter your password';
                        if (_isSignUp && v.length < 6) return 'Use at least 6 characters';
                        return null;
                      },
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submitEmail,
                      child: _loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isSignUp ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _isSignUp = !_isSignUp;
                                _message = null;
                              });
                            },
                      child: Text(_isSignUp ? 'Already have an account? Sign in' : 'Need an account? Sign up'),
                    ),
                    if (!_isSignUp)
                      TextButton(
                        onPressed: _loading ? null : _forgotPassword,
                        child: Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(child: Divider(color: theme.colorScheme.outline)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'or',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                        Expanded(child: Divider(color: theme.colorScheme.outline)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: theme.colorScheme.outline),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
