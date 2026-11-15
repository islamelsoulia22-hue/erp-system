import 'package:flutter/material.dart';

/// Breakpoints: mobile < 600, tablet 600-1024, desktop > 1024.
/// largeDesktop >= 1600 (extra-wide content cap).
abstract final class Breakpoints {
  static const double tablet = 600;
  static const double desktop = 1024;
  static const double largeDesktop = 1600;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isMobile => screenWidth < Breakpoints.tablet;
  bool get isTablet =>
      screenWidth >= Breakpoints.tablet &&
      screenWidth < Breakpoints.desktop;
  bool get isDesktop => screenWidth >= Breakpoints.desktop;

  /// Content padding that grows with the breakpoint.
  /// Mobile takes full width (16), larger screens breathe more (24).
  double get contentPadding => isDesktop
      ? 24
      : isTablet
          ? 20
          : 16;

  /// Column count for grids.
  int columns({int mobile = 2, int tablet = 3, int desktop = 5}) =>
      isDesktop ? desktop : isTablet ? tablet : mobile;
}

/// Builds the right layout per breakpoint with a centered max-width
/// constraint on large screens (1600 — mobile takes full width).
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;
  final double maxWidth;
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
    this.maxWidth = 1600,
  });

  @override
  Widget build(BuildContext context) {
    final body = context.isDesktop
        ? (desktop ?? tablet ?? mobile)
        : context.isTablet
            ? (tablet ?? mobile)
            : mobile;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: body,
      ),
    );
  }
}

/// Padded scrollable page body used by all ERP screens.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  const PageBody({super.key, required this.children, this.padding});

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobile: ListView(
        padding: EdgeInsets.all(context.contentPadding),
        children: children,
      ),
    );
  }
}
