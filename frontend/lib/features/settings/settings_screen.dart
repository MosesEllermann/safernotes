import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zknotes_app/features/auth/auth_controller.dart';
import 'package:zknotes_app/shared/app/app_l10n.dart';
import 'package:zknotes_app/shared/app/app_preferences.dart';
import 'package:zknotes_app/shared/widgets/animated_icon_button.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final prefs = ref.watch(appPreferencesProvider).valueOrNull ??
        const AppPreferences(languageCode: 'en', themeMode: ThemeMode.system);
    final session = ref.watch(authControllerProvider).valueOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 940;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
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
                                icon: Icons.arrow_back_rounded,
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
                            icon: Icons.palette_outlined,
                            title: l10n.t('appearance'),
                            child: SegmentedButton<ThemeMode>(
                              selected: {prefs.themeMode},
                              segments: [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  label: Text(l10n.t('system')),
                                  icon: const Icon(Icons.brightness_auto),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  label: Text(l10n.t('light')),
                                  icon: const Icon(Icons.light_mode),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text(l10n.t('dark')),
                                  icon: const Icon(Icons.dark_mode),
                                ),
                              ],
                              onSelectionChanged: (value) => ref
                                  .read(appPreferencesProvider.notifier)
                                  .setThemeMode(value.first),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _SettingsSection(
                            icon: Icons.translate_rounded,
                            title: l10n.t('language'),
                            child: SegmentedButton<String>(
                              selected: {prefs.languageCode},
                              segments: [
                                ButtonSegment(
                                  value: 'en',
                                  label: Text(l10n.t('english')),
                                ),
                                ButtonSegment(
                                  value: 'de',
                                  label: Text(l10n.t('german')),
                                ),
                              ],
                              onSelectionChanged: (value) => ref
                                  .read(appPreferencesProvider.notifier)
                                  .setLanguage(value.first),
                            ),
                          ),
                          if (!wide) ...[
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
                child: _SecurityPanel(
                  email: session?.email ?? '',
                  inset: const EdgeInsets.fromLTRB(0, 20, 24, 28),
                ),
              ),
          ],
        ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
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
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: scheme.primary),
                const SizedBox(width: 12),
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
                  TextFormField(
                    controller: _currentPassword,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: l10n.t('currentPassword'),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                    validator: (value) {
                      if ((value ?? '').isEmpty) return l10n.t('enterPassword');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newPassword,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: l10n.t('newPassword'),
                      prefixIcon: const Icon(Icons.key_outlined),
                    ),
                    validator: (value) {
                      if ((value ?? '').length < 8) {
                        return l10n.t('passwordMin');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPassword,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: l10n.t('confirmPassword'),
                      prefixIcon: const Icon(Icons.done_all_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscure
                            ? l10n.t('showPassword')
                            : l10n.t('hidePassword'),
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
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
            FilledButton.icon(
              onPressed: _busy ? null : _changePassword,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_reset_rounded),
              label: Text(l10n.t('updatePassword')),
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
    if (value.contains('SocketException')) return l10n.t('serverUnreachable');
    return value.replaceFirst('Exception: ', '');
  }
}
