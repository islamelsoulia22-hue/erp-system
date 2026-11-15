import 'package:flutter/material.dart';

/// Company logo on a white rounded box so it shows on any theme.
class BrandLogo extends StatelessWidget {
  final double size;
  final double radius;
  const BrandLogo({super.key, this.size = 42, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(
          Icons.business_outlined,
          color: Colors.black87,
        ),
      ),
    );
  }
}
