import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/delete_confirm.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../sales/presentation/widgets/barcode_scan_sheet.dart';
import '../../../../core/pdf/barcode_pdf.dart';
import '../../../../core/printing/usb_receipt_printer.dart';
import '../../../../core/printing/xprinter_service.dart';
import '../../data/products_repository.dart';
import '../../domain/product.dart';
import '../providers/products_providers.dart';

class ProductDetailScreen extends ConsumerWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(productDetailProvider(productId));
    final barcodes = ref.watch(productBarcodesProvider(productId));
    final canEdit = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.productsEdit),
          orElse: () => false,
        );
    final isManager = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.isCompanyManager,
          orElse: () => false,
        );

    return detail.when(
      loading: () => const LoadingSkeleton(rows: 5),
      error: (_, _) => const ErrorState(),
      data: (p) {
        if (p == null) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'المنتج غير موجود.',
          );
        }
        return ResponsiveLayout(
          mobile: ListView(
            padding:
                EdgeInsets.all(context.contentPadding),
            children: [
              AppCard(
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color:
                            AppColors.primaryContainer,
                        borderRadius:
                            BorderRadius.circular(10),
                      ),
                      child: const Icon(
                          Icons.inventory_2_outlined,
                          color: AppColors.primary),
                    ),
                    const SizedBox(
                        width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall),
                          Text('SKU: ${p.sku}',
                              textDirection:
                                  TextDirection.ltr,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.end,
                      children: [
                        AppStatus.badge(p.isActive
                            ? 'ACTIVE'
                            : 'INACTIVE'),
                        if (canEdit)
                          IconButton(
                            tooltip: 'تعديل',
                            iconSize: 20,
                            icon: const Icon(
                                Icons.edit_outlined),
                            onPressed: () =>
                                context.push(
                                    '/products/$productId/edit'),
                          ),
                        if (isManager)
                          IconButton(
                            tooltip: 'حذف الصنف',
                            iconSize: 20,
                            icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.danger),
                            onPressed: () =>
                                _deleteProduct(
                                    context,
                                    ref,
                                    productId,
                                    p.name),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (p.description != null) ...[
                const SizedBox(
                    height: AppSpacing.md),
                AppCard(
                  child: Text(p.description!),
                ),
              ],
              const SizedBox(
                  height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                        title: 'البيانات'),
                    _row('الفئة',
                        p.categoryName ?? '—'),
                    _row('الوحدة',
                        p.unitName ?? '—'),
                    _row('المورد',
                        p.supplierName?.isNotEmpty == true
                            ? p.supplierName!
                            : 'غير محدد'),
                    _row('سعر الشراء',
                        AppFormat.money(
                            p.purchasePrice)),
                    _row('سعر البيع',
                        AppFormat.money(
                            p.salePrice)),
                    _row('الحد الأدنى',
                        '${p.minimumStock}'),
                  ],
                ),
              ),
              if (p.barcodeMaterialId != null ||
                  p.labelLengthMm != null) ...[
                const SizedBox(
                    height: AppSpacing.md),
                AppCard(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(
                          title:
                              'بيانات بكر الباركود'),
                      _row(
                          'الخامة',
                          p.barcodeMaterialName ??
                              '—'),
                      if (p.labelLengthMm != null)
                        _row(
                            'الطول (ملي)',
                            '${p.labelLengthMm}'),
                      if (p.labelWidthMm != null)
                        _row(
                            'العرض (ملي)',
                            '${p.labelWidthMm}'),
                      if (p.qtyPerRoll != null)
                        _row(
                            'qty/roll',
                            p.qtyPerRoll!
                                .toStringAsFixed(
                                    0)),
                      _row(
                          'سعر البكرة شراء',
                          AppFormat.money(
                              p.purchasePrice)),
                      _row(
                          'سعر البكرة بيع',
                          AppFormat.money(
                              p.salePrice)),
                    ],
                  ),
                ),
              ],
              if (p.deviceType != null) ...[
                const SizedBox(
                    height: AppSpacing.md),
                AppCard(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(
                          title: 'بيانات الجهاز'),
                      _row('النوع',
                          DeviceTypes.labelOf(
                              p.deviceType!)),
                      if (p.brand != null)
                        _row('الماركة', p.brand!),
                      if (p.model != null)
                        _row('الموديل', p.model!),
                      const SizedBox(height: 8),
                      _SerialsSection(
                          productId: productId),
                    ],
                  ),
                ),
              ],
              const SizedBox(
                  height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('الباركود',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => context.push(
                              '/products/barcodes'),
                          icon: const Icon(
                              Icons
                                  .barcode_reader,
                              size: 18),
                          label: const Text(
                              'قسم الباركود'),
                        ),
                        if (canEdit)
                          TextButton.icon(
                            onPressed: () =>
                                _addBarcodeSheet(
                                    context,
                                    ref,
                                    productId),
                            icon: const Icon(
                                Icons.add_outlined,
                                size: 18),
                            label:
                                const Text('إضافة'),
                          ),
                      ],
                    ),
                    barcodes.when(
                      loading: () =>
                          const LoadingSkeleton(
                              rows: 2),
                      error: (_, _) =>
                          const ErrorState(
                              message:
                                  'تعذر تحميل الباركود.'),
                      data: (list) {
                        if (list.isEmpty) {
                          return Text(
                            'لا يوجد باركود — الباركود اختياري.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall,
                          );
                        }
                        return Column(
                          children: [
                            for (final b in list)
                              ListTile(
                                dense: true,
                                contentPadding:
                                    EdgeInsets.zero,
                                leading: Icon(
                                    b.isPrimary
                                        ? Icons
                                            .star_outlined
                                        : Icons
                                            .barcode_reader,
                                    size: 20),
                                title: Text(b.barcode,
                                    textDirection:
                                        TextDirection
                                            .ltr),
                                subtitle: Text(
                                    '${b.barcodeType}${b.isPrimary ? ' • أساسي' : ''}'),
                                trailing: Row(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip:
                                          'طباعة XPrinter (كل الأنظمة)',
                                      iconSize:
                                          20,
                                      icon:
                                          const Icon(
                                        Icons
                                            .label_outlined,
                                      ),
                                      onPressed:
                                          () async {
                                        await showXPrinterSheet(
                                          context,
                                          [
                                            BarcodeLabelData(
                                              productId:
                                                  productId,
                                              productName:
                                                  p.name,
                                              barcode:
                                                  b.barcode,
                                            ),
                                          ],
                                          initialCopies:
                                              1,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      tooltip:
                                          'طباعة PDF',
                                      iconSize:
                                          20,
                                      icon:
                                          const Icon(
                                        Icons
                                            .print_outlined,
                                      ),
                                      onPressed:
                                          () async {
                                        try {
                                          await printBarcodeLabels(
                                            context,
                                            [
                                              BarcodeLabelData(
                                                productId:
                                                    productId,
                                                productName:
                                                    p.name,
                                                barcode:
                                                    b.barcode,
                                              ),
                                            ],
                                            copies:
                                                1,
                                          );
                                        } catch (
                                            e) {
                                          if (context
                                              .mounted) {
                                            ScaffoldMessenger.of(
                                                    context)
                                                .showSnackBar(
                                              SnackBar(
                                                content:
                                                    Text(
                                                  'تعذر الطباعة: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                    if (supportsUsbReceiptPrint)
                                      IconButton(
                                        tooltip:
                                            'طباعة ريسيت USB',
                                        iconSize:
                                            20,
                                        icon:
                                            const Icon(
                                          Icons
                                              .receipt_long_outlined,
                                        ),
                                        onPressed:
                                            () async {
                                          try {
                                            await printLabelsUsbReceipt(
                                              context,
                                              [
                                                BarcodeLabelData(
                                                  productId:
                                                      productId,
                                                  productName:
                                                      p.name,
                                                  barcode:
                                                      b.barcode,
                                                ),
                                              ],
                                              copies:
                                                  1,
                                            );
                                            if (context
                                                .mounted) {
                                              ScaffoldMessenger.of(
                                                      context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content:
                                                      Text(
                                                    'اتطبعت على الريسيت.',
                                                  ),
                                                ),
                                              );
                                            }
                                          } on UsbPrinterException catch(
                                              e) {
                                            if (context
                                                .mounted) {
                                              await showUsbPrinterError(
                                                context,
                                                e,
                                              );
                                            }
                                          } catch (
                                              e) {
                                            if (context
                                                .mounted) {
                                              ScaffoldMessenger.of(
                                                      context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content:
                                                      Text(
                                                    'تعذر الطباعة: $e',
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    IconButton(
                                      tooltip:
                                          'معاينة الملصق',
                                      iconSize: 20,
                                      icon: const Icon(
                                        Icons
                                            .visibility_outlined,
                                      ),
                                      onPressed: () {
                                        final label =
                                            BarcodeLabelData(
                                          productId:
                                              productId,
                                          productName:
                                              p.name,
                                          barcode:
                                              b.barcode,
                                        );
                                        showBarcodeLabelsPreview(
                                          context,
                                          [
                                            label
                                          ],
                                          copies: 1,
                                          showPdfButton:
                                              true,
                                          onReceiptPrint:
                                              supportsUsbReceiptPrint
                                                  ? () async {
                                                      try {
                                                        await printLabelsUsbReceipt(
                                                          context,
                                                          [
                                                            label
                                                          ],
                                                          copies:
                                                              1,
                                                        );
                                                        if (context
                                                            .mounted) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            const SnackBar(
                                                              content:
                                                                  Text(
                                                                'اتطبعت على الريسيت.',
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      } on UsbPrinterException catch(
                                                          e) {
                                                        if (context
                                                            .mounted) {
                                                          await showUsbPrinterError(
                                                            context,
                                                            e,
                                                          );
                                                        }
                                                      }
                                                    }
                                                  : null,
                                        );
                                      },
                                    ),
                                    if (canEdit)
                                      IconButton(
                                        iconSize: 20,
                                        icon: const Icon(
                                            Icons
                                                .delete_outline),
                                        onPressed:
                                            () async {
                                          try {
                                            await ref
                                                .read(
                                                    productsRepositoryProvider)
                                                .removeBarcode(
                                                    b.id);
                                            ref.invalidate(
                                                productBarcodesProvider(
                                                    productId));
                                            ref.invalidate(
                                                productDetailProvider(
                                                    productId));
                                          } catch (e) {
                                            if (context
                                                .mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                      content: Text(e is AppFailure
                                                          ? e.messageAr
                                                          : 'حدث خطأ أثناء تنفيذ العملية.')));
                                            }
                                          }
                                        },
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteProduct(BuildContext context, WidgetRef ref,
      String id, String name) async {
    if (!await confirmDelete(context, 'الصنف "$name"')) return;
    try {
      await ref.read(productsRepositoryProvider).deleteProduct(id);
      ref
        ..invalidate(productsPageProvider)
        ..invalidate(productDetailProvider(id));
      if (context.mounted) context.pop();
    } catch (e) {
      // لو الحذف النهائي مرفوض بسبب مخزون/حركات مرتبطة، اعرض بدائل:
      // إيقاف (آمن) أو حذف قسري (يمسح الرصيد والحركات).
      if (e is LinkedRecordFailure && context.mounted) {
        final choice = await _linkedDeleteChoice(context, name);
        if (choice == _LinkedChoice.deactivate && context.mounted) {
          try {
            await ref
                .read(productsRepositoryProvider)
                .deactivateProduct(id);
            ref
              ..invalidate(productsPageProvider)
              ..invalidate(productDetailProvider(id));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('تم إيقاف الصنف وإخفاؤه من القوائم.')));
              context.pop();
            }
          } catch (e2) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(deleteErrorMessage(e2))));
            }
          }
        } else if (choice == _LinkedChoice.force && context.mounted) {
          if (!await confirmDelete(context, 'الحذف النهائي القسري "$name" (سيمسح رصيده وحركاته)')) {
            return;
          }
          try {
            await ref
                .read(productsRepositoryProvider)
                .deleteProductForce(id);
            ref
              ..invalidate(productsPageProvider)
              ..invalidate(productDetailProvider(id));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف الصنف نهائيا.')));
              context.pop();
            }
          } catch (e3) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(deleteErrorMessage(e3))));
            }
          }
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(deleteErrorMessage(e))));
      }
    }
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Flexible(
            child: Text(
              v,
              style:
                  const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
  void _addBarcodeSheet(
      BuildContext context, WidgetRef ref, String pid) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom:
              MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('إضافة باركود (يدوي أو مسح)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رقم الباركود',
                prefixIcon:
                    const Icon(Icons.barcode_reader),
                suffixIcon: IconButton(
                  tooltip: 'مسح بالكاميرا',
                  icon: const Icon(
                      Icons.qr_code_scanner_outlined),
                  onPressed: () async {
                    final code =
                        await showModalBottomSheet<
                            String>(
                      context: ctx,
                      showDragHandle: true,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) =>
                          const BarcodeScanSheet(),
                    );
                    if (code != null &&
                        code.isNotEmpty) {
                      ctrl.text = code;
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (ctrl.text.trim().isEmpty) return;
                try {
                  await ref
                      .read(productsRepositoryProvider)
                      .addBarcode(
                          productId: pid,
                          barcode: ctrl.text);
                  ref.invalidate(
                      productBarcodesProvider(pid));
                  ref.invalidate(
                      productDetailProvider(pid));
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                            content: Text(e is AppFailure
                                ? e.messageAr
                                : 'حدث خطأ — ربما الباركود مكرر.')));
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

/// قائمة سيريالات الجهاز (لفئة الإلكترونيات).
class _SerialsSection extends ConsumerWidget {
  final String productId;
  const _SerialsSection({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serials = ref.watch(_serialsProvider(productId));
    return serials.when(
      loading: () => const Center(
          child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2))),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Text('لا توجد سيريالات مسجلة.',
              style: Theme.of(context).textTheme.bodySmall);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('السيريالات (${list.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in list)
                  Chip(
                    label: Text(s,
                        textDirection:
                            TextDirection.ltr,
                        style: const TextStyle(
                            fontSize: 12)),
                    visualDensity:
                        VisualDensity.compact,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

final _serialsProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, id) {
  return ref.watch(productsRepositoryProvider).serialsOf(id);
});

enum _LinkedChoice { cancel, deactivate, force }

/// حوار بدائل الحذف عند وجود مخزون/حركات مرتبطة.
Future<_LinkedChoice> _linkedDeleteChoice(
    BuildContext context, String name) async {
  final res = await showDialog<_LinkedChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تعذر الحذف النهائي'),
      content: Text(
          'الصنف "$name" عليه رصيد مخزون أو حركات مرتبطة.\n\n'
          '• "إيقاف" يخفيه من القوائم ويحافظ على تاريخ الفواتير (آمن).\n'
          '• "حذف قسري" يمسح رصيده وحركاته نهائيا ثم يحذفه.'),
      actions: [
        TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_LinkedChoice.cancel),
            child: const Text('إلغاء')),
        TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_LinkedChoice.deactivate),
            child: const Text('إيقاف الصنف')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
          ),
          onPressed: () =>
              Navigator.of(ctx).pop(_LinkedChoice.force),
          child: const Text('حذف قسري'),
        ),
      ],
    ),
  );
  return res ?? _LinkedChoice.cancel;
}
