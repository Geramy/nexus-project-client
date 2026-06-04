// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Signed-out state: tabbed Login / Register forms. Surfaces the server's
/// validation/auth error messages inline. Register enforces the documented
/// password rules client-side (≥8 chars, uppercase + a non-alphanumeric symbol)
/// before hitting the API, and still shows the server's 400 message if rejected.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/lemonade/api/exceptions.dart';
import '../../../infrastructure/nexus/providers/nexus_account_providers.dart';
import '../../../shared/ui/nexus_ui.dart';

class AccountAuthForms extends ConsumerStatefulWidget {
  const AccountAuthForms({super.key, this.onSkip});

  /// When provided, a "Skip for now" action is shown directly below the
  /// sign-in/register button.
  final VoidCallback? onSkip;

  @override
  ConsumerState<AccountAuthForms> createState() => _AccountAuthFormsState();
}

class _AccountAuthFormsState extends ConsumerState<AccountAuthForms>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    // Rebuild on tab change so the card sizes to the active form (below).
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: NexusCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            glow: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_circle_outlined, size: 28),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Nexus Account',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                Gap.xs,
                Text(
                  'Sign in or create an account to subscribe and run inference.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Gap.lg,
                TabBar(
                  controller: _tabs,
                  tabs: const [
                    Tab(text: 'Sign in'),
                    Tab(text: 'Register'),
                  ],
                ),
                Gap.lg,
                // Size the card to the ACTIVE form (the short Sign-in form no
                // longer gets padded out to the taller Register form's height),
                // so the action button stays near the top.
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: _tabs.index == 0
                      ? const _LoginForm()
                      : const _RegisterForm(),
                ),
                if (widget.onSkip != null) ...[
                  Gap.sm,
                  TextButton(
                    onPressed: widget.onSkip,
                    child: const Text('Skip for now'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _LoginForm extends ConsumerStatefulWidget {
  const _LoginForm();

  @override
  ConsumerState<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<_LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await ref
          .read(nexusAuthProvider.notifier)
          .login(email: _email.text.trim(), password: _password.text);
    } on LemonadeApiException catch (e, st) {
      debugPrint(
        'Nexus login failed (LemonadeApiException): ${e.message}\n$st',
      );
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('Nexus login failed: $e\n$st');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        Gap.md,
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        if (_error != null) ...[Gap.md, _ErrorText(_error!)],
        const SizedBox(height: AppSpacing.lg),
        GradientButton(
          onPressed: _submitting ? null : _submit,
          busy: _submitting,
          expand: true,
          label: 'Sign in',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RegisterForm extends ConsumerStatefulWidget {
  const _RegisterForm();

  @override
  ConsumerState<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends ConsumerState<_RegisterForm> {
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _company.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Documented rules: ≥8 chars, must include an uppercase letter and a
  /// non-alphanumeric symbol. Returns null when valid.
  String? _validatePassword(String value) {
    if (value.length < 8) return 'Password must be at least 8 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must include an uppercase letter.';
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
      return 'Password must include a symbol (non-alphanumeric character).';
    }
    return null;
  }

  Future<void> _submit() async {
    final company = _company.text.trim();
    final email = _email.text.trim();
    final pwd = _password.text;

    if (company.isEmpty) {
      setState(() => _error = 'Company / client name is required.');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = 'Email is required.');
      return;
    }
    final pwdError = _validatePassword(pwd);
    if (pwdError != null) {
      setState(() => _error = pwdError);
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await ref
          .read(nexusAuthProvider.notifier)
          .register(clientName: company, email: email, password: pwd);
    } on LemonadeApiException catch (e, st) {
      debugPrint(
        'Nexus register failed (LemonadeApiException): ${e.message}\n$st',
      );
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('Nexus register failed: $e\n$st');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No inner scroll view: the parent (AccountAuthForms) already scrolls, and
    // this is sized intrinsically by the AnimatedSize wrapper above.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _company,
          decoration: const InputDecoration(
            labelText: 'Company / client name',
            prefixIcon: Icon(Icons.business_outlined),
          ),
        ),
        Gap.md,
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        Gap.md,
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
            helperText: 'Min 8 chars, 1 uppercase, 1 symbol',
            helperMaxLines: 2,
          ),
        ),
        if (_error != null) ...[Gap.md, _ErrorText(_error!)],
        const SizedBox(height: AppSpacing.lg),
        GradientButton(
          onPressed: _submitting ? null : _submit,
          busy: _submitting,
          expand: true,
          label: 'Create account',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(message, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    );
  }
}
