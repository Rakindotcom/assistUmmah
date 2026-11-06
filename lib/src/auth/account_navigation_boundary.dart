import 'dart:async';

import 'package:flutter/material.dart';

/// Own the complete navigation tree per identity, including dialogs and pushed
/// detail routes. Replacing only the home screen leaves old routes visible.
class AccountNavigationBoundary extends StatefulWidget {
  const AccountNavigationBoundary({
    super.key,
    required this.sessionIds,
    required this.initialSessionId,
    required this.child,
    this.onSessionInvalidated,
  });

  final Stream<String?> sessionIds;
  final String? initialSessionId;
  final Widget child;

  /// Called before the replacement navigation tree can schedule new work.
  /// Optional native cleanup must not prevent the identity transition.
  final Future<void> Function()? onSessionInvalidated;

  @override
  State<AccountNavigationBoundary> createState() =>
      _AccountNavigationBoundaryState();
}

class _AccountNavigationBoundaryState extends State<AccountNavigationBoundary> {
  StreamSubscription<String?>? _subscription;
  String? _sessionId;
  int _revision = 0;
  int _subscriptionEpoch = 0;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.initialSessionId;
    _listen();
  }

  void _listen() {
    final epoch = ++_subscriptionEpoch;
    _subscription = widget.sessionIds.listen((id) {
      if (mounted && epoch == _subscriptionEpoch) _transition(id);
    }, onError: (Object error, StackTrace stack) {
      if (mounted && epoch == _subscriptionEpoch) _transition(null);
    });
  }

  void _transition(String? id) {
    if (_sessionId == id) return;
    try {
      final cleanup = widget.onSessionInvalidated?.call();
      if (cleanup != null) unawaited(cleanup.catchError((Object _) {}));
    } catch (_) {
      // A failed optional cleanup must not retain another account's routes.
    }
    setState(() {
      _sessionId = id;
      // Even A -> B -> A within a frame must discard A's previous routes.
      _revision++;
    });
  }

  @override
  void didUpdateWidget(AccountNavigationBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionIds != widget.sessionIds) {
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  @override
  void dispose() {
    _subscriptionEpoch++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: ValueKey(_revision), child: widget.child);
}
