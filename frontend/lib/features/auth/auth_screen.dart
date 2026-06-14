import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  var _registering = false;
  var _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final auth = ref.watch(authControllerProvider);
    final busy = auth.isLoading;
    final error = auth.asError?.error.toString();
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
                          : l10n.t('welcomeBack'),
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 28),
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
                          onPressed: () => setState(() => _obscure = !_obscure),
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
                          : Icon(_registering
                              ? Icons.person_add_alt
                              : Icons.login),
                      label: Text(_registering
                          ? l10n.t('createAccount')
                          : l10n.t('login')),
                    ),
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
    final controller = ref.read(authControllerProvider.notifier);
    if (_registering) {
      await controller.register(
        email: _email.text.trim(),
        password: _password.text,
        workspaceName: _workspace.text.trim(),
      );
    } else {
      await controller.login(
        email: _email.text.trim(),
        password: _password.text,
      );
    }
  }

  String _cleanError(String value, AppL10n l10n) {
    if (value.contains('SocketException')) return l10n.t('serverUnreachable');
    if (value.contains('Invalid credentials')) return l10n.t('badCredentials');
    return value.replaceFirst('Exception: ', '');
  }
}
