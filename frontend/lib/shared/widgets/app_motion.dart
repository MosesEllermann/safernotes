import 'package:flutter/material.dart';

/// Central motion policy for implicit animations.
///
/// Flutter exposes the platform's "remove animations" preference through
/// [MediaQuery.disableAnimations]. Resolving durations here makes every
/// migrated component honor that setting without maintaining parallel widget
/// trees.
abstract final class AppMotion {
  static Duration duration(BuildContext context, Duration normal) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
  }
}
