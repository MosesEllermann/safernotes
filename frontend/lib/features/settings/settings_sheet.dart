import 'package:flutter/material.dart';
import 'package:safernotes_app/features/settings/system_font_setting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';
import 'package:safernotes_app/shared/theme/app_icons.dart';

class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final prefs = ref.watch(appPreferencesProvider).valueOrNull ??
        const AppPreferences(languageCode: 'en', themeMode: ThemeMode.system);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.t('settings'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: l10n.t('close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(l10n.t('language'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              selected: {prefs.languageCode},
              segments: [
                ButtonSegment(value: 'en', label: Text(l10n.t('english'))),
                ButtonSegment(value: 'de', label: Text(l10n.t('german'))),
              ],
              onSelectionChanged: (value) => ref
                  .read(appPreferencesProvider.notifier)
                  .setLanguage(value.first),
            ),
            const SizedBox(height: 18),
            Text(l10n.t('appearance'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              selected: {prefs.themeMode},
              segments: [
                ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(l10n.t('system')),
                    icon: const Icon(AppIcons.brightnessAuto)),
                ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(l10n.t('light')),
                    icon: const Icon(AppIcons.lightMode)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(l10n.t('dark')),
                    icon: const Icon(AppIcons.darkMode)),
              ],
              onSelectionChanged: (value) => ref
                  .read(appPreferencesProvider.notifier)
                  .setThemeMode(value.first),
            ),
            const SizedBox(height: 18),
            const SystemFontSetting(),
          ],
        ),
      ),
    );
  }
}
