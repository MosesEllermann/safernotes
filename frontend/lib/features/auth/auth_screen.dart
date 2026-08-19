import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';

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
  var _submitBusy = false;
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
    final busy = auth.isLoading || _recoveryBusy || _submitBusy;
    final error = _localError ?? auth.asError?.error.toString();
    final title = _registering
        ? l10n.t('createVault')
        : _recovering
            ? l10n.t('recoverVault')
            : l10n.t('welcomeBack');
    final actionLabel = _recovering
        ? (_recoveryRequested
            ? l10n.t('resetPassword')
            : l10n.t('sendRecoveryCode'))
        : _registering
            ? l10n.t('createAccount')
            : l10n.t('login');
    final intro = _AuthIntro(
      title: l10n.t('appName'),
      activeTitle: title,
      recovering: _recovering,
    );
    final form = _AuthPanel(
      l10n: l10n,
      formKey: _formKey,
      title: title,
      modeIcon: _modeIcon(),
      registering: _registering,
      recovering: _recovering,
      recoveryRequested: _recoveryRequested,
      busy: busy,
      obscure: _obscure,
      actionIcon: _actionIcon(),
      actionLabel: actionLabel,
      email: _email,
      password: _password,
      workspace: _workspace,
      code: _code,
      recoveryKey: _recoveryKey,
      newPassword: _newPassword,
      error: error == null ? null : _cleanError(error, l10n, _recovering),
      onModeChanged: (value) => setState(() => _registering = value),
      onTogglePassword: _togglePassword,
      onSubmit: _submit,
      onToggleRecovery: _toggleRecoveryMode,
    );
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 48 : 20,
                  vertical: wide ? 36 : 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 980 : 460),
                  child: Flex(
                    direction: wide ? Axis.horizontal : Axis.vertical,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (wide) Expanded(flex: 9, child: intro) else intro,
                      SizedBox(width: wide ? 48 : 0, height: wide ? 0 : 28),
                      if (wide) Expanded(flex: 8, child: form) else form,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _modeIcon() {
    if (_recovering) return LucideIcons.shieldCheck;
    if (_registering) return LucideIcons.userRoundPlus;
    return LucideIcons.lockKeyhole;
  }

  IconData _actionIcon() {
    if (_recovering) {
      return _recoveryRequested ? LucideIcons.rotateCcwKey : LucideIcons.send;
    }
    return _registering ? LucideIcons.userRoundPlus : LucideIcons.logIn;
  }

  void _togglePassword() => setState(() => _obscure = !_obscure);

  void _toggleRecoveryMode() {
    setState(() {
      _recovering = !_recovering;
      _recoveryRequested = false;
      _localError = null;
      _challenge = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitBusy = true;
      _localError = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    try {
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
    } finally {
      if (mounted) setState(() => _submitBusy = false);
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
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const _AuthMark(icon: LucideIcons.keyRound),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            l10n.t('saveRecoveryKey'),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.t('recoveryKeyHint'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(
                        recoveryKey,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: recoveryKey),
                            ),
                            icon: const Icon(LucideIcons.copy),
                            label: Text(l10n.t('copy')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(l10n.t('done')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _cleanError(String value, AppL10n l10n, bool recovering) {
    if (value.contains('SocketException')) return l10n.t('serverUnreachable');
    if (value.contains('Invalid credentials')) return l10n.t('badCredentials');
    if (value.contains('Invalid recovery code')) {
      return l10n.t('badRecoveryCode');
    }
    if (value.contains('SecretBoxAuthenticationError') ||
        value.contains('authentication')) {
      return l10n.t(recovering ? 'badRecoveryKey' : 'vaultUnlockFailed');
    }
    return value.replaceFirst('Exception: ', '');
  }
}

class _AuthIntro extends StatelessWidget {
  const _AuthIntro({
    required this.title,
    required this.activeTitle,
    required this.recovering,
  });

  final String title;
  final String activeTitle;
  final bool recovering;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(LucideIcons.notebookText,
                  size: 22, color: scheme.onSurface),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 34),
        Text(
          activeTitle,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
        ),
        const SizedBox(height: 14),
        Text(
          recovering
              ? 'Stelle deinen verschlüsselten Tresor mit Recovery-Key und neuem Passwort wieder her.'
              : 'Private Notizen, Checklisten und Erinnerungen bleiben lokal verschlüsselt und klar organisiert.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const [
            _AuthFeaturePill(
                icon: LucideIcons.lockKeyhole, label: 'Zero knowledge'),
            _AuthFeaturePill(icon: LucideIcons.bell, label: 'Erinnerungen'),
            _AuthFeaturePill(
                icon: LucideIcons.listChecks, label: 'Checklisten'),
          ],
        ),
      ],
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.l10n,
    required this.formKey,
    required this.title,
    required this.modeIcon,
    required this.registering,
    required this.recovering,
    required this.recoveryRequested,
    required this.busy,
    required this.obscure,
    required this.actionIcon,
    required this.actionLabel,
    required this.email,
    required this.password,
    required this.workspace,
    required this.code,
    required this.recoveryKey,
    required this.newPassword,
    required this.onModeChanged,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onToggleRecovery,
    this.error,
  });

  final AppL10n l10n;
  final GlobalKey<FormState> formKey;
  final String title;
  final IconData modeIcon;
  final bool registering;
  final bool recovering;
  final bool recoveryRequested;
  final bool busy;
  final bool obscure;
  final IconData actionIcon;
  final String actionLabel;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController workspace;
  final TextEditingController code;
  final TextEditingController recoveryKey;
  final TextEditingController newPassword;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onToggleRecovery;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: formKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.42),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _AuthMark(icon: modeIcon),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (!recovering) ...[
                _AuthModeSwitch(
                  loginLabel: l10n.t('login'),
                  registerLabel: l10n.t('register'),
                  registering: registering,
                  disabled: busy,
                  onChanged: onModeChanged,
                ),
                const SizedBox(height: 20),
              ],
              _AuthTextField(
                controller: email,
                label: l10n.t('email'),
                icon: LucideIcons.atSign,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (!text.contains('@')) return l10n.t('invalidEmail');
                  return null;
                },
              ),
              if (!recovering) ...[
                const SizedBox(height: 12),
                _AuthTextField(
                  controller: password,
                  label: l10n.t('password'),
                  icon: LucideIcons.keyRound,
                  obscureText: obscure,
                  textInputAction:
                      registering ? TextInputAction.next : TextInputAction.done,
                  suffix: _PasswordVisibilityButton(
                    obscure: obscure,
                    onPressed: onTogglePassword,
                  ),
                  validator: (value) {
                    final text = value ?? '';
                    if (registering && text.length < 8) {
                      return l10n.t('passwordMin');
                    }
                    if (!registering && text.isEmpty) {
                      return l10n.t('enterPassword');
                    }
                    return null;
                  },
                ),
              ],
              if (registering) ...[
                const SizedBox(height: 12),
                _AuthTextField(
                  controller: workspace,
                  label: l10n.t('workspace'),
                  icon: LucideIcons.folderLock,
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return l10n.t('nameWorkspace');
                    }
                    return null;
                  },
                ),
              ],
              if (recovering && recoveryRequested) ...[
                const SizedBox(height: 12),
                _AuthTextField(
                  controller: code,
                  label: l10n.t('recoveryCode'),
                  icon: LucideIcons.mailCheck,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if ((value ?? '').trim().length < 6) {
                      return l10n.t('enterRecoveryCode');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _AuthTextField(
                  controller: recoveryKey,
                  label: l10n.t('recoveryKey'),
                  icon: LucideIcons.keySquare,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return l10n.t('enterRecoveryKey');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _AuthTextField(
                  controller: newPassword,
                  label: l10n.t('newPassword'),
                  icon: LucideIcons.keyRound,
                  obscureText: obscure,
                  textInputAction: TextInputAction.done,
                  suffix: _PasswordVisibilityButton(
                    obscure: obscure,
                    onPressed: onTogglePassword,
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
                _AuthError(message: error!),
              ],
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: FilledButton.icon(
                  key: ValueKey(busy),
                  onPressed: busy ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(actionIcon),
                  label: Text(actionLabel),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: busy
                    ? Padding(
                        key: const ValueKey('auth-progress'),
                        padding: const EdgeInsets.only(top: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: const LinearProgressIndicator(minHeight: 3),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('auth-idle')),
              ),
              if (!registering) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: busy ? null : onToggleRecovery,
                  icon: Icon(
                    recovering ? LucideIcons.arrowLeft : LucideIcons.circleHelp,
                  ),
                  label: Text(
                    recovering
                        ? l10n.t('backToLogin')
                        : l10n.t('forgotPassword'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthMark extends StatelessWidget {
  const _AuthMark({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 22, color: scheme.onSurface),
    );
  }
}

class _AuthFeaturePill extends StatelessWidget {
  const _AuthFeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _AuthModeSwitch extends StatelessWidget {
  const _AuthModeSwitch({
    required this.loginLabel,
    required this.registerLabel,
    required this.registering,
    required this.disabled,
    required this.onChanged,
  });

  final String loginLabel;
  final String registerLabel;
  final bool registering;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AuthModeButton(
              icon: LucideIcons.logIn,
              label: loginLabel,
              selected: !registering,
              disabled: disabled,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _AuthModeButton(
              icon: LucideIcons.userRoundPlus,
              label: registerLabel,
              selected: registering,
              disabled: disabled,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthModeButton extends StatelessWidget {
  const _AuthModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: disabled || selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 42,
        decoration: BoxDecoration(
          color: selected ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        suffixIcon: suffix,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.72)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error.withValues(alpha: 0.72)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}

class _PasswordVisibilityButton extends StatelessWidget {
  const _PasswordVisibilityButton({
    required this.obscure,
    required this.onPressed,
  });

  final bool obscure;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: obscure ? 'Passwort anzeigen' : 'Passwort verbergen',
      onPressed: onPressed,
      icon: Icon(obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
    );
  }
}

class _AuthError extends StatelessWidget {
  const _AuthError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.circleAlert, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    height: 1.3,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
