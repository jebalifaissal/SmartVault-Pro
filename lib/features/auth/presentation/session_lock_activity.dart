import 'package:flutter/widgets.dart';

class SessionLockActivityScope extends InheritedWidget {
  const SessionLockActivityScope({
    required this.runWhileExternalActivity,
    required super.child,
    super.key,
  });

  final Future<T> Function<T>(Future<T> Function() action)
  runWhileExternalActivity;

  static Future<T> run<T>(BuildContext context, Future<T> Function() action) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SessionLockActivityScope>();
    return scope == null ? action() : scope.runWhileExternalActivity(action);
  }

  @override
  bool updateShouldNotify(SessionLockActivityScope oldWidget) => false;
}
