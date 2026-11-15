import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_card.dart';

/// Standard search field with icon + clear button.
class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onSubmitted,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_outlined, size: 20),
        suffixIcon: onClear == null
            ? null
            : IconButton(
                iconSize: 20,
                icon: const Icon(Icons.clear_outlined),
                onPressed: () {
                  controller.clear();
                  onClear!();
                },
              ),
      ),
      onSubmitted: onSubmitted,
    );
  }
}

/// Professional empty state with icon + action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48,
                color: theme.colorScheme.outline),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle!,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Professional Arabic error state. Never shows raw errors.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorState(
      {super.key,
      this.message = 'حدث خطأ أثناء تنفيذ العملية، برجاء المحاولة مرة أخرى.',
      this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(message,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('إعادة المحاولة')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Skeleton shimmer for loading lists (no blank screens).
class LoadingSkeleton extends StatelessWidget {
  final int rows;
  const LoadingSkeleton({super.key, this.rows = 6});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.6);
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows,
      separatorBuilder: (_, _) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, _) => AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                height: 13,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(
                        AppRadius.xs))),
            const SizedBox(height: AppSpacing.sm),
            Container(
                height: 11,
                width: 180,
                decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(
                        AppRadius.xs))),
          ],
        ),
      ),
    );
  }
}
