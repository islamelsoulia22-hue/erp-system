import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// مكونات نظام تصميم YAD المشتركة.
/// الحركة: كل حركة أقل من 600ms، والضغط على أي زر scale .92.

const Curve kYadSpring = Cubic(.34, 1.56, .64, 1);

/// تقليل الحركة لو المستخدم مفعّل "تقليل الحركة" في النظام.
Duration yadDuration(BuildContext context, int ms) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true
        ? Duration.zero
        : Duration(milliseconds: ms);

/// يضغط بـscale .92 (200ms spring) بدون ripple.
class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  const TapScale(
      {super.key, required this.child, this.onTap, this.semanticLabel});

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .92 : 1,
          duration: yadDuration(context, 200),
          curve: kYadSpring,
          child: widget.child,
        ),
      ),
    );
  }
}

/// ظهور تدريجي للبطاقات: slide 18px + fade، مع stagger 70ms.
class RiseIn extends StatelessWidget {
  final Widget child;
  final int index;
  const RiseIn({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    final delay = (index * 70).clamp(0, 350);
    final total = 550 + delay;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// مربع أيقونة ملوّن (46/44/38 حسب الحجم).
class YadIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final double size;
  final double radius;
  const YadIconTile({
    super.key,
    required this.icon,
    this.color = AppColors.indigoDeep,
    this.background = AppColors.primaryContainer,
    this.size = 44,
    this.radius = 15,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: color, size: size * .5),
    );
  }
}

/// زر رئيسي بتدرج Indigo → Violet.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool expand;
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final child = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: enabled ? AppColors.actionGradient : null,
        color: enabled ? null : AppColors.neutralContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.indigo.withValues(alpha: .33),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: enabled ? Colors.white : AppColors.neutral,
            ),
          ),
        ],
      ),
    );
    return TapScale(onTap: onPressed, semanticLabel: label, child: child);
  }
}

/// شريحة فلتر دائرية: نشطة = Ink بنص أبيض.
class YadFilterBar extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const YadFilterBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final on = i == selected;
          return TapScale(
            onTap: () => onChanged(i),
            semanticLabel: labels[i],
            child: AnimatedContainer(
              duration: yadDuration(context, 250),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on
                    ? (dark ? AppColors.indigo : AppColors.ink)
                    : theme.colorScheme.surface,
                border: Border.all(
                    color: on
                        ? Colors.transparent
                        : (dark ? AppColors.darkDivider : AppColors.border)),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                  color: on ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// بطاقة هيرو داكنة بتدرج Midnight → Navy (إجماليات وأرقام كبيرة).
class YadHeroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient gradient;
  const YadHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.gradient = AppColors.cardHeroGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: .28),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// عنوان شاشة كبير (26/800) مع إجراء اختياري على الطرف.
class YadScreenHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const YadScreenHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: Theme.of(context).textTheme.headlineLarge),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// ====== الشريط السفلي المتحرك ======
class YadNavDestination {
  final String label;
  final IconData icon;
  final int badge;
  const YadNavDestination(this.label, this.icon, {this.badge = 0});
}

/// شريط سفلي عائم: فقاعة تنزلق بين التبويبات (550ms spring)،
/// الأيقونة النشطة ترتفع داخلها (450ms)، الشارة الحمراء تنبض.
class YadBottomNav extends StatelessWidget {
  final List<YadNavDestination> items;
  final int selected; // -1 = لا شيء
  final ValueChanged<int> onTap;
  const YadBottomNav({
    super.key,
    required this.items,
    required this.selected,
    required this.onTap,
  });

  static const double _barH = 72;
  static const double _bubble = 58;
  static const double _pop = 22;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final noMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: yadDuration(context, 700),
      curve: const Cubic(.2, .9, .3, 1.15),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
            offset: Offset(0, 110 * (1 - t)), child: child),
      ),
      child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: _barH + _pop + 4,
          child: LayoutBuilder(builder: (context, c) {
            final inner = c.maxWidth - 18;
            final itemW = inner / items.length;
            final idx = selected < 0 ? 0 : selected;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 0,
                  height: _barH,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.midnight.withValues(alpha: .4),
                          blurRadius: 44,
                          offset: const Offset(0, 22),
                        ),
                      ],
                    ),
                  ),
                ),
                if (selected >= 0)
                  AnimatedPositionedDirectional(
                    duration: noMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 550),
                    curve: kYadSpring,
                    start: 9 + idx * itemW + (itemW - _bubble) / 2,
                    bottom: _barH + _pop - _bubble,
                    width: _bubble,
                    height: _bubble,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.actionGradient,
                          shape: BoxShape.circle,
                          border: Border.all(color: bg, width: 6),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.indigo.withValues(alpha: .45),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                PositionedDirectional(
                  start: 9,
                  end: 9,
                  bottom: 0,
                  height: _barH,
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavItem(
                            dest: items[i],
                            active: i == selected,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final YadNavDestination dest;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(
      {required this.dest, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : AppColors.navInactive;
    return TapScale(
      onTap: onTap,
      semanticLabel: dest.label,
      child: SizedBox(
        height: 72,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSlide(
                    duration: yadDuration(context, 450),
                    curve: kYadSpring,
                    offset: Offset(0, active ? -21 / 24 : 0),
                    child: AnimatedScale(
                      duration: yadDuration(context, 450),
                      curve: kYadSpring,
                      scale: active ? 1.15 : 1,
                      child: Icon(dest.icon, size: 24, color: color),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: yadDuration(context, 250),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      height: 16 / 11,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: color,
                    ),
                    child: Text(dest.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            if (dest.badge > 0)
              PositionedDirectional(
                top: 11,
                end: 14,
                child: PulseBadge(count: dest.badge),
              ),
          ],
        ),
      ),
    );
  }
}

/// شارة حمراء بنبضة 1.6s.
class PulseBadge extends StatefulWidget {
  final int count;
  const PulseBadge({super.key, required this.count});

  @override
  State<PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<PulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Container(
        constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.coral,
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: AppColors.coral.withValues(alpha: .6 * (1 - _c.value)),
              spreadRadius: 10 * _c.value,
            ),
          ],
        ),
        child: child,
      ),
      child: Text(
        widget.count > 99 ? '99+' : '${widget.count}',
        style: const TextStyle(
          fontFamily: 'Cairo',
          color: Colors.white,
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}


/// حركة عائمة هادئة (translateY 0 → -8) تتكرر، للخلفيات في الهيرو.
class Floating extends StatefulWidget {
  final Widget child;
  final Duration period;
  final double dy;
  const Floating({
    super.key,
    required this.child,
    this.period = const Duration(seconds: 7),
    this.dy = 8,
  });

  @override
  State<Floating> createState() => _FloatingState();
}

class _FloatingState extends State<Floating>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -widget.dy * Curves.easeInOut.transform(_c.value)),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// منحنى المبيعات الصغير في الهيرو (128×64) بنقطة في النهاية.
class HeroSparkline extends StatelessWidget {
  const HeroSparkline({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 128,
        height: 64,
        child: CustomPaint(painter: _SparkPainter()),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const c = Color(0xFF5BF0C8);
    final path = Path()
      ..moveTo(2, 52)
      ..cubicTo(22, 50, 28, 30, 48, 34)
      ..cubicTo(68, 38, 78, 54, 92, 30)
      ..cubicTo(106, 6, 114, 12, 126, 6);
    canvas.drawPath(
      path,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(const Offset(126, 6), 5, Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
