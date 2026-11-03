import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/auth_controller.dart';
import '../services/auth_service.dart';
import '../theme/auth_theme.dart';

class AuthScreen extends StatefulWidget {
  final AuthController auth;
  const AuthScreen({super.key, required this.auth});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _feedback = GlobalKey();
  final _name = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController(),
      _code = TextEditingController();
  late final TextEditingController _email;
  bool _savedCode = false;
  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.auth.email);
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final a = widget.auth;
    final requestedPage = a.page;
    switch (a.page) {
      case AuthPage.signup:
        await a.signup(_name.text, _email.text, _password.text);
      case AuthPage.login:
        await a.login(_email.text, _password.text);
      case AuthPage.forgot:
        await a.recover(_email.text, _code.text);
      case AuthPage.reset:
        await a.reset(_password.text);
      case AuthPage.saveRecovery:
        return;
    }
    if (!mounted ||
        a.page != requestedPage ||
        a.authenticated ||
        a.message.isEmpty) {
      return;
    }
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final feedbackContext = _feedback.currentContext;
    if (feedbackContext != null && feedbackContext.mounted) {
      await Scrollable.ensureVisible(
        feedbackContext,
        alignment: .5,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.auth;
    final signup = a.page == AuthPage.signup,
        login = a.page == AuthPage.login,
        reset = a.page == AuthPage.reset,
        recovery = a.page == AuthPage.saveRecovery;
    final title = switch (a.page) {
      AuthPage.login => 'Welcome back',
      AuthPage.signup => 'Create Account',
      AuthPage.forgot => 'Forgot password?',
      AuthPage.reset => 'Set a new password',
      AuthPage.saveRecovery => 'Save your recovery code',
    };
    final subtitle = switch (a.page) {
      AuthPage.login => 'Sign in to your HomeEase account.',
      AuthPage.signup =>
        'Your home, connected.\nCreate an account on this phone.',
      AuthPage.forgot => 'Enter your email and the recovery code you saved when you created your account.',
      AuthPage.reset => 'Choose a new password for your local account.',
      AuthPage.saveRecovery => 'Keep this code somewhere safe outside the app. You will need it if you forget your password.',
    };
    return Theme(
      data: buildAuthTheme(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AuthColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          body: CustomPaint(
            painter: const _AuthBackdrop(),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: AutofillGroup(
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: AuthColors.accent,
                                  letterSpacing: -.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: login ? 17 : 14,
                                fontWeight: login
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                height: 1.45,
                              ),
                            ),
                            SizedBox(height: login ? 56 : 36),
                            if (recovery) ...[
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AuthColors.field,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AuthColors.border),
                                ),
                                child: SelectableText(
                                  a.recoveryCode ?? '',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    height: 1.8,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'This code is shown only now. Anyone with it can reset your password. After a password reset, save the replacement code; the old one will stop working.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AuthColors.muted,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _savedCode,
                                onChanged: (value) =>
                                    setState(() => _savedCode = value ?? false),
                                title: const Text(
                                  'I have saved my recovery code',
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _savedCode
                                    ? a.acknowledgeRecoveryCode
                                    : null,
                                child: Text(
                                  a.session == null
                                      ? 'Continue to sign in'
                                      : 'Continue to HomeEase',
                                ),
                              ),
                            ] else ...[
                              if (signup) ...[
                                TextFormField(
                                  controller: _name,
                                  autofillHints: const [AutofillHints.name],
                                  textCapitalization: TextCapitalization.words,
                                  maxLength: 80,
                                  decoration: const InputDecoration(
                                    labelText: 'Full name',
                                    counterText: '',
                                  ),
                                  validator: (v) =>
                                      (v?.trim().isNotEmpty ?? false)
                                      ? null
                                      : 'Enter your full name.',
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (!reset) ...[
                                TextFormField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Email address',
                                  ),
                                  validator: validateEmail,
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (login || signup || reset) ...[
                                PasswordField(
                                  controller: _password,
                                  label: reset ? 'New password' : 'Password',
                                  newPassword: !login,
                                  validator: login
                                      ? (v) => (v?.isNotEmpty ?? false)
                                            ? null
                                            : 'Enter your password.'
                                      : validatePassword,
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (signup || reset) ...[
                                PasswordField(
                                  controller: _confirm,
                                  label: 'Confirm password',
                                  newPassword: true,
                                  validator: (v) =>
                                      v == _password.text &&
                                          (v?.isNotEmpty ?? false)
                                      ? null
                                      : 'Passwords do not match.',
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Use at least 8 characters for your password.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AuthColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                              if (a.page == AuthPage.forgot) ...[
                                TextFormField(
                                  controller: _code,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  maxLength: 64,
                                  decoration: const InputDecoration(
                                    labelText: 'Recovery code',
                                    counterText: '',
                                  ),
                                  validator: (v) =>
                                      RegExp(r'^[A-F0-9]{32}$').hasMatch(
                                        LocalAuthRepository.normalizeCode(
                                          v ?? '',
                                        ),
                                      )
                                      ? null
                                      : 'Enter your saved recovery code.',
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'Recovery works only for an account saved on this phone. No email is sent.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AuthColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (login) ...[
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: a.busy
                                        ? null
                                        : () => a.navigate(AuthPage.forgot),
                                    child: const Text('Forgot your password?'),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                              if (a.message.isNotEmpty)
                                Padding(
                                  key: _feedback,
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: _AuthNotice(text: a.message),
                                  ),
                                ),
                              FilledButton(
                                onPressed: a.busy || !a.configured
                                    ? null
                                    : _submit,
                                child: a.busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AuthColors.accent,
                                        ),
                                      )
                                    : Text(switch (a.page) {
                                        AuthPage.signup => 'Sign up',
                                        AuthPage.login => 'Sign in',
                                        AuthPage.forgot =>
                                          'Verify recovery code',
                                        _ => 'Update password',
                                      }),
                              ),
                              const SizedBox(height: 22),
                              TextButton(
                                onPressed: a.busy
                                    ? null
                                    : () {
                                        if (a.recovering) {
                                          a.logout();
                                        } else {
                                          a.navigate(
                                            login
                                                ? AuthPage.signup
                                                : AuthPage.login,
                                          );
                                        }
                                      },
                                style: TextButton.styleFrom(
                                  foregroundColor: AuthColors.text,
                                ),
                                child: Text(
                                  login
                                      ? 'Create new account'
                                      : signup
                                      ? 'Already have an account? Sign in'
                                      : 'Back to login',
                                ),
                              ),
                              if (login) ...[
                                TextButton.icon(
                                  onPressed: a.busy ? null : a.enterDemo,
                                  icon: const Icon(
                                    Icons.explore_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Explore local demo'),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Accounts are saved on this phone. No internet or email verification required.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AuthColors.muted,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
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

class _AuthNotice extends StatelessWidget {
  final String text;
  const _AuthNotice({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AuthColors.field,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AuthColors.border),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12, height: 1.45)),
  );
}

class _AuthBackdrop extends CustomPainter {
  const _AuthBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final wash = Paint()
      ..shader = RadialGradient(
        center: Alignment.topRight,
        radius: 1.1,
        colors: [AuthColors.accent.withValues(alpha: .055), Colors.transparent],
      ).createShader(bounds);
    canvas.drawRect(bounds, wash);
  }

  @override
  bool shouldRepaint(covariant _AuthBackdrop oldDelegate) => false;
}

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool newPassword;
  final String? Function(String?)? validator;
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.newPassword = false,
    this.validator,
  });
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _hidden,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    validator: widget.validator,
    decoration: InputDecoration(
      labelText: widget.label,
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: _hidden
            ? 'Show ${widget.label.toLowerCase()}'
            : 'Hide ${widget.label.toLowerCase()}',
        onPressed: () => setState(() => _hidden = !_hidden),
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}
