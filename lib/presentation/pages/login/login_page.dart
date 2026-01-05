import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/utils/error_handler.dart';

/// Modern minimal login page with animations
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Animation controller for error shake
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  Future<void> _login() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      _triggerShake();
      _showError('Please enter email and password');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.signIn(_emailCtrl.text.trim(), _passCtrl.text);
    } catch (e) {
      _triggerShake();
      if (mounted) {
        _showError(AppErrorHandler.parse(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _triggerShake() {
    _shakeController.forward(from: 0);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade400,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),

              // Logo/Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Icon(
                  Icons.fingerprint_rounded,
                  size: 40,
                  color: scheme.primary,
                ),
              )
                  .animate()
                  .fade(duration: 600.ms)
                  .slideY(begin: -0.5, end: 0, curve: Curves.easeOutBack),

              const SizedBox(height: 32),

              // Title
              Text(
                'Welcome back',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  letterSpacing: -1.0,
                ),
              ).animate().fade(delay: 200.ms).slideX(begin: -0.1),

              const SizedBox(height: 8),

              Text(
                'Sign in to your account to continue',
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ).animate().fade(delay: 300.ms).slideX(begin: -0.1),

              const SizedBox(height: 48),

              // Login form container with Shake animation
              AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(
                        10 *
                            (
                                // Math: sin(progress * pi * wraps) * decay
                                (1 - _shakeController.value) *
                                    ((_shakeController.value * 20)
                                            .remainder(2) -
                                        1)),
                        0),
                    child: child,
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Email field
                    Text(
                      'Email',
                      style: textTheme.titleSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ).animate().fade(delay: 400.ms),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: scheme.onSurface),
                      decoration: const InputDecoration(
                        hintText: 'Enter your email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ).animate().fade(delay: 450.ms).slideY(begin: 0.2),
                    const SizedBox(height: 20),

                    // Password field
                    Text(
                      'Password',
                      style: textTheme.titleSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ).animate().fade(delay: 500.ms),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(color: scheme.onSurface),
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ).animate().fade(delay: 550.ms).slideY(begin: 0.2),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Login button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    disabledBackgroundColor: scheme.primary.withOpacity(0.6),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Text('Sign In'),
                ),
              ).animate().fade(delay: 700.ms).scale(),

              const SizedBox(height: 24),

              // Footer
              Center(
                child: Text(
                  'Smart Attendance System',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ).animate().fade(delay: 900.ms),
            ],
          ),
        ),
      ),
    );
  }
}
