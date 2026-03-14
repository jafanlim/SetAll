import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/auth_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/biometric_service.dart';

/// Login screen: Email + password with visibility toggle and Google OAuth.
/// Mirrors the premium dark aesthetic of [RegisterScreen].
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ── Palette (mirrors landing page: #0F172A slate, #14B8A6 teal) ────────────
  static const Color _bg          = Color(0xFF0F172A);
  static const Color _surface     = Color(0xFF1E293B);
  static const Color _surfaceCard = Color(0xFF334155);
  static const Color _teal        = Color(0xFF14B8A6);
  static const Color _tealDim     = Color(0xFF0D9488);
  static const Color _onSurface   = Color(0xFFF1F5F9);
  static const Color _subtle      = Color(0xFF94A3B8);
  static const Color _outline     = Color(0xFF475569);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocus    = FocusNode();
  final _passwordFocus = FocusNode();

  bool _loading      = false;
  bool _showPassword = false;
  String? _message;
  bool _isSuccess    = false;

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
      final email    = _emailController.text.trim();
      final password = _passwordController.text;
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (mounted) {
        final bio    = BiometricService.instance;
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
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = e.message;
          _isSuccess = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = e.toString();
          _isSuccess = false;
        });
      }
    }
  }

  /// Base URL for email/OAuth redirects so confirmation and Google redirect work on mobile (e.g. open link on iPhone).
  String? _authRedirectUrl() {
    if (kAuthRedirectBaseUrl.isNotEmpty) {
      // Custom scheme deep links (e.g. com.jafa.setall://login-callback) must
      // not have a trailing slash added — return them verbatim on native.
      // On web, the custom scheme is invalid; use the browser origin instead.
      if (!kAuthRedirectBaseUrl.startsWith('http')) {
        if (kIsWeb) return '${Uri.base.origin}/login';
        return kAuthRedirectBaseUrl;
      }
      return kAuthRedirectBaseUrl.endsWith('/') ? kAuthRedirectBaseUrl : '$kAuthRedirectBaseUrl/';
    }
    if (kIsWeb) {
      return '${Uri.base.origin}/login';
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
        // externalBrowser lets the OS handle the com.jafa.setall:// redirect
        // and return to the app automatically. platformDefault opens an
        // in-app SFSafariViewController on iOS that never auto-dismisses.
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
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
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned(
            top: -80, left: -60,
            child: _GlowBlob(color: _teal.withValues(alpha: 0.18), size: 320),
          ),
          Positioned(
            bottom: 40, right: -80,
            child: _GlowBlob(color: _tealDim.withValues(alpha: 0.12), size: 260),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 36),
                      _buildForm(),
                      const SizedBox(height: 24),
                      _buildLinks(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _teal.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.wallet_rounded, color: _teal, size: 28),
        ),
        const SizedBox(height: 20),
        const Text(
          'Welcome back',
          style: TextStyle(
            color: _onSurface, fontSize: 26,
            fontWeight: FontWeight.w700, letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Sign in to your SetAll account.',
          style: TextStyle(color: _subtle, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _outline.withValues(alpha: 0.6)),
      ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Email ──────────────────────────────────────────────────────
              _label('Email address'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                style: const TextStyle(color: _onSurface),
                decoration: _inputDecoration(
                  hint: 'you@example.com',
                  prefixIcon: Icons.email_outlined,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter your email';
                  if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Password ───────────────────────────────────────────────────
              _label('Password'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submitEmail(),
                style: const TextStyle(color: _onSurface),
                decoration: _inputDecoration(
                  hint: 'Your password',
                  prefixIcon: Icons.lock_outline_rounded,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: _subtle, size: 20,
                    ),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your password';
                  return null;
                },
              ),

              // ── Forgot password ────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _forgotPassword,
                  style: TextButton.styleFrom(
                    foregroundColor: _teal,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  ),
                  child: const Text('Forgot password?', style: TextStyle(fontSize: 13)),
                ),
              ),

              // ── Message banner ─────────────────────────────────────────────
              if (_message != null) ...[
                const SizedBox(height: 8),
                _LoginMessageBanner(message: _message!, isSuccess: _isSuccess),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 12),

              // ── Sign in button ─────────────────────────────────────────────
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submitEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: const Color(0xFF0F172A),
                    disabledBackgroundColor: _tealDim.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF0F172A),
                          ),
                        )
                      : const Text(
                          'Sign in',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Divider ────────────────────────────────────────────────────
              Row(children: [
                const Expanded(child: Divider(color: _outline)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('or',
                      style: TextStyle(
                          color: _subtle.withValues(alpha: 0.8), fontSize: 13)),
                ),
                const Expanded(child: Divider(color: _outline)),
              ]),

              const SizedBox(height: 20),

              // ── Google ─────────────────────────────────────────────────────
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 24,
                      color: _onSurface),
                  label: const Text('Continue with Google',
                      style: TextStyle(color: _onSurface, fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: _outline.withValues(alpha: 0.8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Don't have an account? ",
            style: TextStyle(color: _subtle, fontSize: 14)),
        GestureDetector(
          onTap: _loading ? null : () => context.go(AppRouter.register),
          child: const Text(
            'Sign up',
            style: TextStyle(
              color: _teal, fontSize: 14, fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _onSurface, fontSize: 13, fontWeight: FontWeight.w500,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _subtle, fontSize: 14),
      prefixIcon: Icon(prefixIcon, color: _subtle, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _surfaceCard.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _outline.withValues(alpha: 0.8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _teal, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),
      errorStyle: TextStyle(color: Colors.red.shade300, fontSize: 12),
    );
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────────

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _LoginMessageBanner extends StatelessWidget {
  const _LoginMessageBanner({required this.message, required this.isSuccess});
  final String message;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF14B8A6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isSuccess
            ? teal.withValues(alpha: 0.12)
            : Colors.red.shade900.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess
              ? teal.withValues(alpha: 0.4)
              : Colors.red.shade700.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSuccess
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: isSuccess ? teal : Colors.red.shade300,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isSuccess ? teal : Colors.red.shade300,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
