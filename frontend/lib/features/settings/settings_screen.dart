import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';
import 'package:safernotes_app/shared/providers.dart';
import 'package:safernotes_app/shared/widgets/animated_icon_button.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final prefs = ref.watch(appPreferencesProvider).valueOrNull ??
        const AppPreferences(languageCode: 'en', themeMode: ThemeMode.system);
    final session = ref.watch(authControllerProvider).valueOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 940;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 40 : 20,
                        20,
                        wide ? 32 : 20,
                        28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AppIconButton(
                                tooltip: l10n.t('back'),
                                icon: LucideIcons.arrowLeft,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                l10n.t('settings'),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          _SettingsSection(
                            icon: LucideIcons.palette,
                            title: l10n.t('appearance'),
                            child: _PreferenceOptionGroup<ThemeMode>(
                              value: prefs.themeMode,
                              onChanged: (value) => ref
                                  .read(appPreferencesProvider.notifier)
                                  .setThemeMode(value),
                              options: [
                                _PreferenceOption(
                                  value: ThemeMode.system,
                                  label: l10n.t('system'),
                                  icon: LucideIcons.monitorCog,
                                ),
                                _PreferenceOption(
                                  value: ThemeMode.light,
                                  label: l10n.t('light'),
                                  icon: LucideIcons.sun,
                                ),
                                _PreferenceOption(
                                  value: ThemeMode.dark,
                                  label: l10n.t('dark'),
                                  icon: LucideIcons.moon,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          _SettingsSection(
                            icon: LucideIcons.languages,
                            title: l10n.t('language'),
                            child: _PreferenceOptionGroup<String>(
                              value: prefs.languageCode,
                              onChanged: (value) => ref
                                  .read(appPreferencesProvider.notifier)
                                  .setLanguage(value),
                              options: [
                                _PreferenceOption(
                                  value: 'en',
                                  label: l10n.t('english'),
                                  icon: LucideIcons.languages,
                                ),
                                _PreferenceOption(
                                  value: 'de',
                                  label: l10n.t('german'),
                                  icon: LucideIcons.messageSquareText,
                                ),
                              ],
                            ),
                          ),
                          if (!wide) ...[
                            const SizedBox(height: 18),
                            _BillingPanel(
                              accessToken: session?.accessToken ?? '',
                              tenant: session?.defaultTenant ?? '',
                              inset: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 18),
                            _SecurityPanel(
                              email: session?.email ?? '',
                              inset: EdgeInsets.zero,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (wide)
              SizedBox(
                width: 390,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _BillingPanel(
                        accessToken: session?.accessToken ?? '',
                        tenant: session?.defaultTenant ?? '',
                        inset: const EdgeInsets.fromLTRB(0, 20, 24, 18),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SecurityPanel(
                        email: session?.email ?? '',
                        inset: const EdgeInsets.fromLTRB(0, 0, 24, 28),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BillingPanel extends ConsumerStatefulWidget {
  const _BillingPanel({
    required this.accessToken,
    required this.tenant,
    required this.inset,
  });

  final String accessToken;
  final String tenant;
  final EdgeInsets inset;

  @override
  ConsumerState<_BillingPanel> createState() => _BillingPanelState();
}

class _BillingPanelState extends ConsumerState<_BillingPanel> {
  late Future<SubscriptionInfo?> _subscriptionFuture;
  String? _busyPlan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscriptionFuture = _loadSubscription();
  }

  @override
  void didUpdateWidget(covariant _BillingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accessToken != widget.accessToken ||
        oldWidget.tenant != widget.tenant) {
      _subscriptionFuture = _loadSubscription();
    }
  }

  Future<SubscriptionInfo?> _loadSubscription() async {
    if (widget.accessToken.isEmpty || widget.tenant.isEmpty) return null;
    return ref.read(apiClientProvider).fetchSubscription(
          accessToken: widget.accessToken,
          tenant: widget.tenant,
        );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: widget.inset,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.56),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: FutureBuilder<SubscriptionInfo?>(
          future: _subscriptionFuture,
          builder: (context, snapshot) {
            final subscription = snapshot.data;
            final plan = subscription?.plan ?? 'free';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.sparkles,
                        color: scheme.onSurfaceVariant, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Plan',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _planTitle(plan),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 18),
                _PlanOptionCard(
                  title: 'Essential',
                  price: '18 €/Jahr',
                  description: '1,50 €/Monat, jährlich abgerechnet',
                  icon: LucideIcons.badgeCheck,
                  selected: plan == 'essential',
                  busy: _busyPlan == 'essential',
                  onPressed: plan == 'essential'
                      ? null
                      : () => _startCheckout('essential'),
                ),
                const SizedBox(height: 10),
                _PlanOptionCard(
                  title: 'Pro',
                  price: '60 €/Jahr',
                  description: '5 €/Monat, mehr Speicher und Kollaboration',
                  icon: LucideIcons.crown,
                  selected: plan == 'pro',
                  busy: _busyPlan == 'pro',
                  onPressed: plan == 'pro' ? null : () => _startCheckout('pro'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _planTitle(String plan) {
    return switch (plan) {
      'essential' => 'Aktuell: Essential',
      'pro' => 'Aktuell: Pro',
      'team' => 'Aktuell: Team',
      'enterprise' => 'Aktuell: Enterprise',
      _ => 'Aktuell: Free',
    };
  }

  Future<void> _startCheckout(String plan) async {
    setState(() {
      _busyPlan = plan;
      _error = null;
    });
    try {
      final session = await ref.read(apiClientProvider).createCheckout(
            accessToken: widget.accessToken,
            tenant: widget.tenant,
            plan: plan,
          );
      if (!mounted) return;
      if (session.checkoutUrl == null || session.checkoutUrl!.isEmpty) {
        setState(() {
          _error = 'Checkout ist noch nicht konfiguriert (${session.status}).';
        });
        return;
      }
      await _showCheckoutDialog(session.checkoutUrl!);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busyPlan = null);
    }
  }

  Future<void> _showCheckoutDialog(String checkoutUrl) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Checkout öffnen'),
          content: SelectableText(
            checkoutUrl,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Schließen'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: checkoutUrl));
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(LucideIcons.copy, size: 16),
              label: const Text('Link kopieren'),
            ),
          ],
        );
      },
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.title,
    required this.price,
    required this.description,
    required this.icon,
    required this.selected,
    required this.busy,
    required this.onPressed,
  });

  final String title;
  final String price;
  final String description;
  final IconData icon;
  final bool selected;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.82)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurface),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                price,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          _SettingsActionButton(
            label: selected ? 'Aktiver Plan' : 'Auswählen',
            icon: selected ? LucideIcons.check : LucideIcons.arrowUpRight,
            busy: busy,
            onPressed: selected ? null : onPressed,
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.56),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                Icon(icon, color: scheme.onSurfaceVariant, size: 18),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _PreferenceOption<T> {
  const _PreferenceOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

class _PreferenceOptionGroup<T> extends StatelessWidget {
  const _PreferenceOptionGroup({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<_PreferenceOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in options)
          _PreferenceOptionTile<T>(
            option: option,
            selected: option.value == value,
            onTap: () => onChanged(option.value),
          ),
      ],
    );
  }
}

class _PreferenceOptionTile<T> extends StatefulWidget {
  const _PreferenceOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _PreferenceOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PreferenceOptionTile<T>> createState() =>
      _PreferenceOptionTileState<T>();
}

class _PreferenceOptionTileState<T> extends State<_PreferenceOptionTile<T>> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: widget.selected
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.92)
                : _hovered
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.42)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                widget.option.icon,
                size: 18,
                color: widget.selected
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.option.label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight:
                            widget.selected ? FontWeight.w700 : FontWeight.w500,
                        color: widget.selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                ),
              ),
              AnimatedScale(
                scale: widget.selected ? 1 : 0.76,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: widget.selected ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Icon(
                    LucideIcons.check,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityPanel extends ConsumerStatefulWidget {
  const _SecurityPanel({
    required this.email,
    required this.inset,
  });

  final String email;
  final EdgeInsets inset;

  @override
  ConsumerState<_SecurityPanel> createState() => _SecurityPanelState();
}

class _SecurityPanelState extends ConsumerState<_SecurityPanel> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  var _busy = false;
  var _obscure = true;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: widget.inset,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.56),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(LucideIcons.shieldCheck,
                    color: scheme.onSurfaceVariant, size: 19),
                const SizedBox(width: 10),
                Text(
                  l10n.t('security'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.email,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 28),
            Text(
              l10n.t('changePassword'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  _SettingsPasswordField(
                    controller: _currentPassword,
                    obscureText: _obscure,
                    label: l10n.t('currentPassword'),
                    icon: LucideIcons.lockKeyhole,
                    validator: (value) {
                      if ((value ?? '').isEmpty) return l10n.t('enterPassword');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _SettingsPasswordField(
                    controller: _newPassword,
                    obscureText: _obscure,
                    label: l10n.t('newPassword'),
                    icon: LucideIcons.keyRound,
                    validator: (value) {
                      if ((value ?? '').length < 8) {
                        return l10n.t('passwordMin');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _SettingsPasswordField(
                    controller: _confirmPassword,
                    obscureText: _obscure,
                    label: l10n.t('confirmPassword'),
                    icon: LucideIcons.checkCheck,
                    suffix: AppIconButton(
                      tooltip: _obscure
                          ? l10n.t('showPassword')
                          : l10n.t('hidePassword'),
                      icon: _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: (value) {
                      if (value != _newPassword.text) {
                        return l10n.t('passwordsDoNotMatch');
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 12),
              Text(_success!, style: TextStyle(color: scheme.primary)),
            ],
            const SizedBox(height: 18),
            _SettingsActionButton(
              label: l10n.t('updatePassword'),
              icon: LucideIcons.rotateCcwKey,
              busy: _busy,
              onPressed: _busy ? null : _changePassword,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = ref.read(l10nProvider);
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: _currentPassword.text,
            newPassword: _newPassword.text,
          );
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      if (mounted) {
        setState(() => _success = l10n.t('passwordUpdated'));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _cleanPasswordError(error.toString(), l10n));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cleanPasswordError(String value, AppL10n l10n) {
    if (value.contains('Current password is incorrect')) {
      return l10n.t('currentPasswordIncorrect');
    }
    if (value.contains('SocketException') ||
        value.contains('ClientException') ||
        value.contains('Server unreachable') ||
        value.contains('timed out')) {
      return l10n.t('serverUnreachable');
    }
    return value.replaceFirst('Exception: ', '');
  }
}

class _SettingsPasswordField extends StatelessWidget {
  const _SettingsPasswordField({
    required this.controller,
    required this.obscureText,
    required this.label,
    required this.icon,
    required this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final bool obscureText;
  final String label;
  final IconData icon;
  final FormFieldValidator<String> validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 5),
                TextFormField(
                  controller: controller,
                  obscureText: obscureText,
                  validator: validator,
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 8),
            suffix!,
          ],
        ],
      ),
    );
  }
}

class _SettingsActionButton extends StatefulWidget {
  const _SettingsActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  State<_SettingsActionButton> createState() => _SettingsActionButtonState();
}

class _SettingsActionButtonState extends State<_SettingsActionButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 48,
          decoration: BoxDecoration(
            color: enabled
                ? (_hovered
                    ? scheme.onSurface.withValues(alpha: 0.9)
                    : scheme.onSurface)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: widget.busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.surface,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 17, color: scheme.surface),
                    const SizedBox(width: 9),
                    Text(
                      widget.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.surface,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
