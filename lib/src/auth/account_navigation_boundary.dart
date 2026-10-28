import 'package:flutter/material.dart';

/// Own the complete navigation tree per identity, including dialogs and pushed
/// detail routes. Replacing only the home screen leaves old routes visible.
class AccountNavigationBoundary extends StatelessWidget {
  const AccountNavigationBoundary({
    super.key,
    required this.sessionIds,
    required this.initialSessionId,
    required this.child,
  });

  final Stream<String?> sessionIds;
  final String? initialSessionId;
  final Widget child;

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
        stream: sessionIds,
        initialData: initialSessionId,
        builder: (context, snapshot) => KeyedSubtree(
          key: ValueKey(snapshot.hasError ? null : snapshot.data),
          child: child,
        ),
      );
}
