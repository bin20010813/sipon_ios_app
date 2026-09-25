import 'package:flutter/widgets.dart';

/// Keeps the iOS bounce at the leading edge while preventing trailing
/// overscroll from exposing the page background below floating navigation.
class BottomClampingBouncingScrollPhysics extends BouncingScrollPhysics {
  const BottomClampingBouncingScrollPhysics({super.parent});

  @override
  BottomClampingBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return BottomClampingBouncingScrollPhysics(
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (position.maxScrollExtent <= position.pixels &&
        position.pixels < value) {
      return value - position.pixels;
    }

    if (position.pixels < position.maxScrollExtent &&
        position.maxScrollExtent < value) {
      return value - position.maxScrollExtent;
    }

    return super.applyBoundaryConditions(position, value);
  }
}
