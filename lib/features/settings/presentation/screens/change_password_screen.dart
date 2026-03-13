import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/haptic_utils.dart';

const _teal  = Color(0xFF00D9B0);
const _slate = Color(0xFF94A3B8);

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentCtrl  = TextEditingController();
  final _newCtrl      = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  bool _obscureCurrent = true;
  bool _obscureNew     = true;
  bool _obscureConfirm = true;
  bool _saving         = false;
  String? _errorMsg;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _saving = true; _errorMsg = null; });

    try {
      final client = Supabase.instance.client;
      final email  = client.auth.currentUser?.email;
      if (email == null) throw Exception('Not signed in');

      // Re-authenticate with current password first.
      await client.auth.signInWithPassword(
        email:    email,
        password: _currentCtrl.text.trim(),
      );

      // Then update to new password.
      await client.auth.updateUser(
        UserAttributes(password: _newCtrl.text.trim()),
      );

      if (!mounted) return;
      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated'),
          backgroundColor: _teal,
        ),
      );
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      setState(() => _errorMsg = e.message);
    } catch (e) {
      setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Change Password',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Current password
              TextFormField(
                controller:   _currentCtrl,
                obscureText:  _obscureCurrent,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, color: _slate),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18, color: _slate,
                    ),
                    onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // New password
              TextFormField(
                controller:   _newCtrl,
                obscureText:  _obscureNew,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_reset_rounded, color: _teal),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18, color: _slate,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 8) return 'At least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Confirm new password
              TextFormField(
                controller:   _confirmCtrl,
                obscureText:  _obscureConfirm,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: const Icon(Icons.lock_reset_rounded, color: _teal),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18, color: _slate,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v != _newCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),

              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMsg!,
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
                ),
              ],

              const SizedBox(height: 28),

              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black54),
                      )
                    : const Text('Update Password',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
