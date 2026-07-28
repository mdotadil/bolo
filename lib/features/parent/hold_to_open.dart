import 'dart:async';
import 'package:flutter/material.dart';

const _gateMs = int.fromEnvironment('BOLO_GATE_MS', defaultValue: 3000);

/// Press-and-hold gate. Deliberately boring: no countdown, no feedback,
/// nothing for a child to find interesting. Early release is a no-op.
class HoldToOpen extends StatefulWidget {
  const HoldToOpen(
      {super.key, required this.child, required this.onOpen, this.holdDuration});
  final Widget child;
  final VoidCallback onOpen;
  final Duration? holdDuration;

  @override
  State<HoldToOpen> createState() => _HoldToOpenState();
}

class _HoldToOpenState extends State<HoldToOpen> {
  Timer? _timer;

  Duration get _duration =>
      widget.holdDuration ?? const Duration(milliseconds: _gateMs);

  void _start(_) {
    _timer?.cancel();
    _timer = Timer(_duration, widget.onOpen);
  }

  void _cancel([dynamic _]) {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        identifier: 'grownup-gate',
        button: true,
        label: 'parent mode',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _start,
          onTapUp: _cancel,
          onTapCancel: _cancel,
          child: widget.child,
        ),
      );
}
