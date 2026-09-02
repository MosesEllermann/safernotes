import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safernotes_app/shared/theme/app_icons.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';

Future<bool> showRecoveryKeyConfirmationDialog({
  required BuildContext context,
  required AppL10n l10n,
  required String recoveryKey,
  required bool rotating,
}) async {
  var confirmed = false;
  var copied = false;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          final scheme = Theme.of(context).colorScheme;
          return AlertDialog(
            icon: const Icon(AppIcons.keyRound),
            title: Text(
              l10n.t(rotating
                  ? 'recoveryRotationTitle'
                  : 'recoveryOnboardingTitle'),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.t(rotating
                          ? 'recoveryRotationBody'
                          : 'recoveryOnboardingBody'),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        recoveryKey,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: recoveryKey),
                        );
                        setDialogState(() => copied = true);
                      },
                      icon: Icon(copied ? AppIcons.check : AppIcons.copy),
                      label: Text(l10n.t(copied ? 'copied' : 'copy')),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.t('recoveryKeyNeverStored'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                    if (rotating) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.t('oldRecoveryKeyInvalid'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: confirmed,
                      onChanged: (value) =>
                          setDialogState(() => confirmed = value ?? false),
                      title: Text(l10n.t('savedRecoveryConfirmation')),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.t('cancel')),
              ),
              FilledButton(
                onPressed: confirmed
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: Text(l10n.t('continueAction')),
              ),
            ],
          );
        },
      ),
    ),
  );
  return result ?? false;
}
