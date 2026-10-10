import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Draws a visible focus ring for buttons, list items and dialog controls alike.
class TvNavigation extends StatefulWidget {
  const TvNavigation({required this.child, super.key});
  final Widget child;

  @override
  State<TvNavigation> createState() => _TvNavigationState();
}

class _TvNavigationState extends State<TvNavigation> {
  final _surface = GlobalKey();
  Rect? _focusRect;
  bool _scheduled = false;
  late final FocusHighlightStrategy _previousStrategy;

  @override
  void initState() {
    super.initState();
    _previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    FocusManager.instance.addListener(_focusChanged);
    _scheduleUpdate();
  }

  void _focusChanged() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null && context.mounted) {
      Scrollable.ensureVisible(context, alignment: .5, duration: const Duration(milliseconds: 150));
    }
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final target = FocusManager.instance.primaryFocus?.context?.findRenderObject();
      final surface = _surface.currentContext?.findRenderObject();
      Rect? rect;
      if (target is RenderBox &&
          target.attached &&
          target.hasSize &&
          surface is RenderBox &&
          surface.attached &&
          surface.hasSize) {
        final offset = target.localToGlobal(Offset.zero) - surface.localToGlobal(Offset.zero);
        final candidate = offset & target.size;
        if (candidate.width > 0 &&
            candidate.height > 0 &&
            candidate.width < surface.size.width &&
            candidate.overlaps(Offset.zero & surface.size)) {
          rect = candidate.inflate(1);
        }
      }
      if (_focusRect != rect) setState(() => _focusRect = rect);
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    FocusManager.instance.highlightStrategy = _previousStrategy;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleUpdate();
    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.select): ActivateIntent()},
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _scheduleUpdate();
            return false;
          },
          child: Stack(
            key: _surface,
            fit: StackFit.expand,
            children: [
              widget.child,
              if (_focusRect case final rect?)
                Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('tv-focus-ring'),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFFFD600),
                          width: 1 / MediaQuery.devicePixelRatioOf(context),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
