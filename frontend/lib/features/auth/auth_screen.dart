import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/theme/app_icons.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/auth/recovery_key_dialog.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';
import 'package:safernotes_app/shared/widgets/app_canvas.dart';
import 'package:safernotes_app/shared/widgets/safernotes_logo.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _workspace = TextEditingController();
  String? _workspaceDefault;
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
    final workspaceDefault = l10n.t('personalVault');
    if (_workspace.text.isEmpty || _workspace.text == _workspaceDefault) {
      _workspace.text = workspaceDefault;
    }
    _workspaceDefault = workspaceDefault;
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
      l10n: l10n,
      title: l10n.t('appName'),
      activeTitle: title,
      recovering: _recovering,
    );
    Widget form({
      required bool showModeSwitch,
      required bool showBrand,
    }) =>
        _AuthPanel(
          l10n: l10n,
          formKey: _formKey,
          title: title,
          modeIcon: _modeIcon(),
          registering: _registering,
          recovering: _recovering,
          recoveryRequested: _recoveryRequested,
          busy: busy,
          obscure: _obscure,
          showModeSwitch: showModeSwitch,
          showBrand: showBrand,
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
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          return _AuthBackdrop(
            child: SafeArea(
              child: compact
                  ? _CompactAuthLayout(
                      registering: _registering,
                      child: form(showModeSwitch: true, showBrand: true),
                    )
                  : _WideAuthLayout(
                      intro: intro,
                      form: form(showModeSwitch: true, showBrand: false),
                    ),
            ),
          );
        },
      ),
    );
  }

  IconData _modeIcon() {
    if (_recovering) return AppIcons.shieldCheck;
    if (_registering) return AppIcons.userRoundPlus;
    return AppIcons.lockKeyhole;
  }

  IconData _actionIcon() {
    if (_recovering) {
      return _recoveryRequested ? AppIcons.rotateCcwKey : AppIcons.send;
    }
    return _registering ? AppIcons.userRoundPlus : AppIcons.logIn;
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
    if (_submitBusy ||
        _recoveryBusy ||
        ref.read(authControllerProvider).isLoading) {
      return;
    }
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
        final material = await controller.prepareRegistration(
          password: _password.text,
          workspaceName: _workspace.text.trim(),
        );
        if (!mounted) return;
        final confirmed = await showRecoveryKeyConfirmationDialog(
          context: context,
          l10n: ref.read(l10nProvider),
          recoveryKey: material.recoveryKey,
          rotating: false,
        );
        if (!confirmed || !mounted) return;
        await controller.completeRegistration(
          email: _email.text.trim(),
          password: _password.text,
          locale: ref.read(l10nProvider).languageCode,
          material: material,
        );
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

  String _cleanError(String value, AppL10n l10n, bool recovering) {
    if (value.contains('SocketException') ||
        value.contains('ClientException') ||
        value.contains('Server unreachable') ||
        value.contains('timed out')) {
      return l10n.t('serverUnreachable');
    }
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

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCanvas(child: child);
  }
}

class _CompactAuthLayout extends StatelessWidget {
  const _CompactAuthLayout({
    required this.registering,
    required this.child,
  });

  final bool registering;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height > 48 ? height - 48 : 0),
        child: Center(
          child: ConstrainedBox(
            key: ValueKey(
              registering ? 'mobile-register-page' : 'mobile-login-page',
            ),
            constraints: const BoxConstraints(maxWidth: 460),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _WideAuthLayout extends StatelessWidget {
  const _WideAuthLayout({
    required this.intro,
    required this.form,
  });

  final Widget intro;
  final Widget form;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
    );
  }
}

class _AuthIntro extends StatelessWidget {
  const _AuthIntro({
    required this.l10n,
    required this.title,
    required this.activeTitle,
    required this.recovering,
  });

  final AppL10n l10n;
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
            const SafernotesLogo(size: 44),
            const SizedBox(width: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        const SizedBox(height: 34),
        Text(
          activeTitle,
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 14),
        Text(
          l10n.t(recovering ? 'recoveryIntro' : 'authIntro'),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _AuthFeaturePill(
                icon: AppIcons.lockKeyhole, label: l10n.t('zeroKnowledge')),
            _AuthFeaturePill(icon: AppIcons.bell, label: l10n.t('reminders')),
            _AuthFeaturePill(
                icon: AppIcons.listChecks, label: l10n.t('checklist')),
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
    required this.showModeSwitch,
    required this.showBrand,
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
  final bool showModeSwitch;
  final bool showBrand;
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
    final design = context.safernotesTheme;

    void submitOrAdvance(String _) {
      if (busy) return;
      if (formKey.currentState?.validate() ?? false) {
        onSubmit();
      } else {
        FocusScope.of(context).nextFocus();
      }
    }

    return Form(
      key: formKey,
      child: AutofillGroup(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: [
              BoxShadow(
                color: design.glassShadow,
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: _FrostedCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showBrand) ...[
                    Row(
                      children: [
                        const SafernotesLogo(size: 34),
                        const SizedBox(width: 10),
                        Text(
                          l10n.t('appName'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                  Row(
                    children: [
                      _AuthMark(icon: modeIcon),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (!recovering && showModeSwitch) ...[
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
                    icon: AppIcons.atSign,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: busy ? null : submitOrAdvance,
                    autofillHints: registering
                        ? const [AutofillHints.newUsername, AutofillHints.email]
                        : const [AutofillHints.username, AutofillHints.email],
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
                      icon: AppIcons.keyRound,
                      obscureText: obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: registering
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      onFieldSubmitted: busy ? null : (_) => onSubmit(),
                      suffix: _PasswordVisibilityButton(
                        l10n: l10n,
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
                      icon: AppIcons.folderLock,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: busy ? null : (_) => onSubmit(),
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
                      icon: AppIcons.mailCheck,
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
                      icon: AppIcons.keySquare,
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
                      icon: AppIcons.keyRound,
                      obscureText: obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: busy ? null : (_) => onSubmit(),
                      suffix: _PasswordVisibilityButton(
                        l10n: l10n,
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
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.xl),
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
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                              child:
                                  const LinearProgressIndicator(minHeight: 3),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('auth-idle')),
                  ),
                  if (!registering) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: busy ? null : onToggleRecovery,
                      icon: Icon(
                        recovering ? AppIcons.arrowLeft : AppIcons.circleHelp,
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
    final design = context.safernotesTheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(design.controlRadius),
      ),
      child: Icon(icon, size: 22, color: scheme.onPrimaryContainer),
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
    final design = context.safernotesTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: design.glassFill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: design.glassStroke),
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
    final design = context.safernotesTheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: design.glassFill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: design.glassStroke),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AuthModeButton(
              icon: AppIcons.logIn,
              label: loginLabel,
              selected: !registering,
              disabled: disabled,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _AuthModeButton(
              icon: AppIcons.userRoundPlus,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected
        ? (dark ? const Color(0xff17201f) : Colors.white)
        : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      onTap: disabled || selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 46,
        decoration: BoxDecoration(
          color: selected
              ? (dark ? Colors.white : scheme.onSurface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
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
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
    this.autofillHints,
    this.onFieldSubmitted,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onFieldSubmitted;
  final bool obscureText;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final fieldFill = dark
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.88)
        : scheme.surface.withValues(alpha: 0.98);
    final fieldStroke = dark
        ? scheme.outline.withValues(alpha: 0.62)
        : scheme.outline.withValues(alpha: 0.42);
    final radius = BorderRadius.circular(AppRadii.pill);
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onFieldSubmitted: onFieldSubmitted,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.96),
        ),
        floatingLabelStyle: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(
          icon,
          size: 18,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.96),
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: fieldFill,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: fieldStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: fieldStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: 0.92),
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: scheme.error.withValues(alpha: 0.82),
            width: 1.2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}

class _PasswordVisibilityButton extends StatelessWidget {
  const _PasswordVisibilityButton({
    required this.l10n,
    required this.obscure,
    required this.onPressed,
  });

  final AppL10n l10n;
  final bool obscure;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: l10n.t(obscure ? 'showPassword' : 'hidePassword'),
      onPressed: onPressed,
      icon: Icon(obscure ? AppIcons.eye : AppIcons.eyeOff, size: 18),
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
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.circleAlert, size: 18, color: scheme.error),
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

/// Frosted container used by the auth panels.
class _FrostedCard extends StatelessWidget {
  const _FrostedCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final design = context.safernotesTheme;
    final radius = BorderRadius.circular(AppRadii.card);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: design.glassFill,
        borderRadius: radius,
        border: Border.all(color: design.glassStroke),
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: radius,
      child: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? surface
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: surface,
            ),
    );
  }
}
