import 'package:flutter/material.dart';

const appInfoBarDuration = Duration(seconds: 4);

/// Shows short-lived, replaceable feedback without leaving actionable
/// snackbars pinned indefinitely on newer Flutter versions.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showAppInfoBar(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = appInfoBarDuration,
  bool avoidMobileNavigation = false,
  ScaffoldMessengerState? messenger,
}) {
  final target = messenger ?? ScaffoldMessenger.maybeOf(context);
  if (target == null) return null;

  final mobile =
      (MediaQuery.maybeOf(context)?.size.width ?? double.infinity) < 700;
  final margin = avoidMobileNavigation && mobile
      ? const EdgeInsets.fromLTRB(16, 0, 16, 96)
      : const EdgeInsets.fromLTRB(16, 0, 16, 16);

  target.clearSnackBars();
  return target.showSnackBar(
    SnackBar(
      duration: duration,
      persist: false,
      behavior: SnackBarBehavior.floating,
      margin: margin,
      dismissDirection: DismissDirection.horizontal,
      content: Text(message),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              onPressed: () {
                target.hideCurrentSnackBar(
                  reason: SnackBarClosedReason.action,
                );
                onAction?.call();
              },
            ),
    ),
  );
}
