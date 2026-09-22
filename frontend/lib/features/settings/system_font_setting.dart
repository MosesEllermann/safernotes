import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';

class SystemFontSetting extends ConsumerWidget {
  const SystemFontSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final enabled =
        ref.watch(appPreferencesProvider).valueOrNull?.useSystemFont ?? false;
    return SwitchListTile.adaptive(
      key: const ValueKey('system-font-setting'),
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.t('useSystemFont')),
      subtitle: Text(l10n.t('useSystemFontDescription')),
      value: enabled,
      onChanged: (value) =>
          ref.read(appPreferencesProvider.notifier).setUseSystemFont(value),
    );
  }
}
