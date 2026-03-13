import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/auth_config.dart';
import '../../../../core/router/app_router.dart';

/// Registration screen with teal/slate dark theme matching the SetAll landing page.
/// Provides email, password, and confirm-password fields with visibility toggles.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ── Palette (mirrors landing page: #0F172A slate, #14B8A6 teal) ────────────
  static const Color _bg          = Color(0xFF0F172A);
  static const Color _surface     = Color(0xFF1E293B);
  static const Color _surfaceCard = Color(0xFF334155);
  static const Color _teal        = Color(0xFF14B8A6);
  static const Color _tealDim     = Color(0xFF0D9488);
  static const Color _onSurface   = Color(0xFFF1F5F9);
  static const Color _subtle      = Color(0xFF94A3B8);
  static const Color _outline     = Color(0xFF475569);

  final _formKey               = GlobalKey<FormState>();
  final _emailController       = TextEditingController();
  final _passwordController    = TextEditingController();
  final _confirmController     = TextEditingController();

  final _emailFocus            = FocusNode();
  final _passwordFocus         = FocusNode();
  final _confirmFocus          = FocusNode();

  bool _loading         = false;
  bool _showPassword    = false;
  bool _showConfirm     = false;
  String? _message;
  bool _isSuccess       = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  String? _authRedirectUrl() {
    if (kAuthRedirectBaseUrl.isNotEmpty) {
      return kAuthRedirectBaseUrl;
    }
    return null;
  }

  Future<void> _submit() async {
    _message = null;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        emailRedirectTo: _authRedirectUrl(),
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _isSuccess = true;
          _message = 'Account created! Check your email to confirm your address, then sign in.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() { _loading = false; _message = e.message; _isSuccess = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _message = e.toString(); _isSuccess = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Ambient glow blobs — matching landing page aesthetic
          Positioned(
            top: -80,
            left: -60,
            child: _GlowBlob(color: _teal.withValues(alpha: 0.18), size: 320),
          ),
          Positioned(
            bottom: 40,
            right: -80,
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
                      _buildSignInLink(),
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
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _teal.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.wallet_rounded, color: _teal, size: 28),
        ),
        const SizedBox(height: 20),
        const Text(
          'Create your account',
          style: TextStyle(
            color: _onSurface,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Split expenses with anyone, anywhere.',
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
              // ── Email ───────────────────────────────────────────────────────
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

              // ── Password ────────────────────────────────────────────────────
              _label('Password'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                style: const TextStyle(color: _onSurface),
                decoration: _inputDecoration(
                  hint: 'Min. 6 characters',
                  prefixIcon: Icons.lock_outline_rounded,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: _subtle,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter a password';
                  if (v.length < 6) return 'Use at least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ── Confirm Password ────────────────────────────────────────────
              _label('Confirm password'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _confirmController,
                focusNode: _confirmFocus,
                obscureText: !_showConfirm,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                style: const TextStyle(color: _onSurface),
                decoration: _inputDecoration(
                  hint: 'Re-enter your password',
                  prefixIcon: Icons.lock_outline_rounded,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: _subtle,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _showConfirm = !_showConfirm),
                    tooltip: _showConfirm ? 'Hide password' : 'Show password',
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please confirm your password';
                  if (v != _passwordController.text) return 'Passwords do not match';
                  return null;
                },
              ),

              // ── Message banner ──────────────────────────────────────────────
              if (_message != null) ...[
                const SizedBox(height: 20),
                _MessageBanner(message: _message!, isSuccess: _isSuccess),
              ],

              const SizedBox(height: 28),

              // ── Submit button ───────────────────────────────────────────────
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: const Color(0xFF0F172A),
                    disabledBackgroundColor: _tealDim.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF0F172A),
                          ),
                        )
                      : const Text(
                          'Create account',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignInLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Already have an account? ', style: TextStyle(color: _subtle, fontSize: 14)),
        GestureDetector(
          onTap: _loading ? null : () => context.go(AppRouter.login),
          child: const Text(
            'Sign in',
            style: TextStyle(
              color: _teal,
              fontSize: 14,
              fontWeight: FontWeight.w600,
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
        color: _onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w500,
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
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: const SizedBox.shrink(),
      ),
    );
  }
}


class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isSuccess});
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
          color: isSuccess ? teal.withValues(alpha: 0.4) : Colors.red.shade700.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSuccess ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
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
