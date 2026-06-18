import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:zknotes_app/features/auth/auth_controller.dart';
import 'package:zknotes_app/shared/app/app_l10n.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _workspace = TextEditingController(text: 'Personal vault');
  final _code = TextEditingController();
  final _recoveryKey = TextEditingController();
  final _newPassword = TextEditingController();
  var _registering = false;
  var _recovering = false;
  var _recoveryRequested = false;
  var _recoveryBusy = false;
  var _obscure = true;
  RecoveryChallenge? _challenge;
  String? _localError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _workspace.dispose();
    _code.dispose();
    _recoveryKey.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final auth = ref.watch(authControllerProvider);
    final busy = auth.isLoading || _recoveryBusy;
    final error = _localError ?? auth.asError?.error.toString();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_outline, size: 44),
                    const SizedBox(height: 20),
                    Text(
                      _registering
                          ? l10n.t('createVault')
                          : _recovering
                              ? l10n.t('recoverVault')
                              : l10n.t('welcomeBack'),
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 28),
                    if (!_recovering) ...[
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                              value: false,
                              label: Text(l10n.t('login')),
                              icon: const Icon(Icons.login)),
                          ButtonSegment(
                              value: true,
                              label: Text(l10n.t('register')),
                              icon: const Icon(Icons.person_add_alt)),
                        ],
                        selected: {_registering},
                        onSelectionChanged: busy
                            ? null
                            : (value) =>
                                setState(() => _registering = value.first),
                      ),
                      const SizedBox(height: 20),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.t('email'),
                        prefixIcon: const Icon(Icons.alternate_email),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (!text.contains('@')) return l10n.t('invalidEmail');
                        return null;
                      },
                    ),
                    if (!_recovering) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: _registering
                            ? TextInputAction.next
                            : TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l10n.t('password'),
                          prefixIcon: const Icon(Icons.key_outlined),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? l10n.t('showPassword')
                                : l10n.t('hidePassword'),
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (value) {
                          final text = value ?? '';
                          if (_registering && text.length < 8) {
                            return l10n.t('passwordMin');
                          }
                          if (!_registering && text.isEmpty) {
                            return l10n.t('enterPassword');
                          }
                          return null;
                        },
                      ),
                    ],
                    if (_registering) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _workspace,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l10n.t('workspace'),
                          prefixIcon: const Icon(Icons.workspaces_outline),
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return l10n.t('nameWorkspace');
                          }
                          return null;
                        },
                      ),
                    ],
                    if (_recovering && _recoveryRequested) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l10n.t('recoveryCode'),
                          prefixIcon: const Icon(Icons.mark_email_read),
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().length < 6) {
                            return l10n.t('enterRecoveryCode');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _recoveryKey,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l10n.t('recoveryKey'),
                          prefixIcon: const Icon(Icons.vpn_key_outlined),
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return l10n.t('enterRecoveryKey');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _newPassword,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l10n.t('newPassword'),
                          prefixIcon: const Icon(Icons.key_outlined),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? l10n.t('showPassword')
                                : l10n.t('hidePassword'),
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (value) {
                          if ((value ?? '').length < 8) {
                            return l10n.t('passwordMin');
                          }
                          return null;
                        },
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _cleanError(error, l10n),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: busy ? null : _submit,
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_recovering
                              ? (_recoveryRequested
                                  ? Icons.lock_reset
                                  : Icons.mark_email_unread)
                              : _registering
                                  ? Icons.person_add_alt
                                  : Icons.login),
                      label: Text(_recovering
                          ? (_recoveryRequested
                              ? l10n.t('resetPassword')
                              : l10n.t('sendRecoveryCode'))
                          : _registering
                              ? l10n.t('createAccount')
                              : l10n.t('login')),
                    ),
                    if (!_registering) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  _recovering = !_recovering;
                                  _recoveryRequested = false;
                                  _localError = null;
                                  _challenge = null;
                                }),
                        icon: Icon(_recovering
                            ? Icons.arrow_back
                            : Icons.help_outline),
                        label: Text(_recovering
                            ? l10n.t('backToLogin')
                            : l10n.t('forgotPassword')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_recovering) {
      if (_recoveryRequested) {
        await _completeRecovery();
      } else {
        await _requestRecovery();
      }
      return;
    }
    final controller = ref.read(authControllerProvider.notifier);
    if (_registering) {
      final recoveryKey = await controller.register(
        email: _email.text.trim(),
        password: _password.text,
        workspaceName: _workspace.text.trim(),
      );
      if (mounted && recoveryKey != null) {
        await _showRecoveryKeyDialog(recoveryKey);
      }
    } else {
      await controller.login(
        email: _email.text.trim(),
        password: _password.text,
      );
    }
  }

  Future<void> _requestRecovery() async {
    setState(() {
      _recoveryBusy = true;
      _localError = null;
    });
    try {
      final challenge =
          await ref.read(authControllerProvider.notifier).startPasswordRecovery(
                email: _email.text.trim(),
              );
      if (!mounted) return;
      if (challenge == null) {
        setState(() => _localError = ref.read(l10nProvider).t('noRecovery'));
      } else {
        setState(() {
          _challenge = challenge;
          _recoveryRequested = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _localError = error.toString());
    } finally {
      if (mounted) setState(() => _recoveryBusy = false);
    }
  }

  Future<void> _completeRecovery() async {
    final challenge = _challenge;
    if (challenge == null) return;
    await ref.read(authControllerProvider.notifier).completePasswordRecovery(
          email: _email.text.trim(),
          code: _code.text.trim(),
          recoveryKey: _recoveryKey.text.trim(),
          newPassword: _newPassword.text,
          recoveryWrapper: challenge.recoveryWrapper,
        );
  }

  Future<void> _showRecoveryKeyDialog(String recoveryKey) {
    final l10n = ref.read(l10nProvider);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('saveRecoveryKey')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.t('recoveryKeyHint')),
            const SizedBox(height: 12),
            SelectableText(
              recoveryKey,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(
              ClipboardData(text: recoveryKey),
            ),
            icon: const Icon(Icons.copy),
            label: Text(l10n.t('copy')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('done')),
          ),
        ],
      ),
    );
  }

  String _cleanError(String value, AppL10n l10n) {
    if (value.contains('SocketException')) return l10n.t('serverUnreachable');
    if (value.contains('Invalid credentials')) return l10n.t('badCredentials');
    if (value.contains('Invalid recovery code')) {
      return l10n.t('badRecoveryCode');
    }
    if (value.contains('SecretBoxAuthenticationError') ||
        value.contains('authentication')) {
      return l10n.t('badRecoveryKey');
    }
    return value.replaceFirst('Exception: ', '');
  }
}
