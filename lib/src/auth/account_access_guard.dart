import 'dart:async';

import 'package:flutter/material.dart';

/// Revokes pushed private routes when the deletion marker appears or its
/// listener fails. The active deletion flow is allowed to finish; identity
/// changes are handled separately by AccountNavigationBoundary.
class AccountAccessGuard extends StatefulWidget {
  const AccountAccessGuard({
    super.key,
    required this.blockedStates,
    required this.allowedBuilder,
    required this.blockedBuilder,
    required this.onAccessRevoked,
  });

  static const deletionRoute = '/account-deletion';
  final Stream<bool> blockedStates;
  final WidgetBuilder allowedBuilder;
  final Widget Function(BuildContext context, bool failed) blockedBuilder;
  final Future<void> Function() onAccessRevoked;

  @override
  State<AccountAccessGuard> createState() => _AccountAccessGuardState();
}

class _AccountAccessGuardState extends State<AccountAccessGuard> {
  StreamSubscription<bool>? _subscription;
  bool? _blocked;
  bool _failed = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    final epoch = ++_epoch;
    _subscription = widget.blockedStates.listen((blocked) {
      if (mounted && epoch == _epoch) _update(blocked, failed: false);
    }, onError: (Object error, StackTrace stack) {
      if (mounted && epoch == _epoch) _update(true, failed: true);
    });
  }

  void _update(bool blocked, {required bool failed}) {
    if (blocked && _blocked != true) {
      try {
        unawaited(widget.onAccessRevoked().catchError((Object _) {}));
      } catch (_) {
        // Native notification failures cannot keep private screens accessible.
      }
      Navigator.of(context).popUntil((route) =>
          route.isFirst ||
          route.settings.name == AccountAccessGuard.deletionRoute);
    }
    setState(() {
      _blocked = blocked;
      _failed = failed;
    });
  }

  @override
  void didUpdateWidget(AccountAccessGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blockedStates != widget.blockedStates) {
      unawaited(_subscription?.cancel());
      _blocked = null;
      _failed = false;
      _listen();
    }
  }

  @override
  void dispose() {
    _epoch++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_blocked == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _blocked!
        ? widget.blockedBuilder(context, _failed)
        : widget.allowedBuilder(context);
  }
}
