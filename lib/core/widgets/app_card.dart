import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'yad_widgets.dart';

/// Dense ERP card. No huge paddings.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.mdx),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
            color: dark ? AppColors.darkDivider : AppColors.border),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF283278).withValues(alpha: .07),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return TapScale(onTap: onTap, child: card);
  }
}

/// Section title with optional action (e.g. "عرض الكل").
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: theme.textTheme.headlineSmall),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Compact KPI card: value + icon + optional delta line.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color containerColor;
  final String? footer;
  final VoidCallback? onTap;
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.containerColor,
    this.footer,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          YadIconTile(
            icon: icon,
            color: color,
            background: containerColor,
            size: 38,
            radius: 13,
          ),
          const SizedBox(height: 10),
          Text(label,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(value,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(height: 1.2, fontSize: 21),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (footer != null)
            Text(footer!,
                style:
                    theme.textTheme.labelSmall?.copyWith(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Compact icon+label quick action button.
class QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final Color? tint;
  const QuickActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.tint,
  });

  QuickActionButton styled({bool primary = false, Color? tint}) =>
      QuickActionButton(
        label: label,
        icon: icon,
        onTap: onTap,
        primary: primary,
        tint: tint,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return TapScale(
      onTap: onTap,
      semanticLabel: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: primary ? AppColors.actionGradient : null,
              color: primary ? null : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
              border: primary
                  ? null
                  : Border.all(
                      color: dark
                          ? AppColors.darkDivider
                          : AppColors.border),
              boxShadow: primary
                  ? [
                      BoxShadow(
                        color: AppColors.indigo.withValues(alpha: .35),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon,
                color: primary
                    ? Colors.white
                    : (tint ?? AppColors.indigoDeep),
                size: 26),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
