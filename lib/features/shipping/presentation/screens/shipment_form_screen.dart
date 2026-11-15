import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../sales/data/sales_repository.dart';
import '../../data/shipping_repository.dart';

class ShipmentFormScreen extends ConsumerStatefulWidget {
  final String? invoiceId;
  const ShipmentFormScreen({super.key, this.invoiceId});
  @override
  ConsumerState<ShipmentFormScreen> createState() =>
      _ShipmentFormScreenState();
}

class _ShipmentFormScreenState
    extends ConsumerState<ShipmentFormScreen> {
  final _company = TextEditingController();
  final _tracking = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _cost = TextEditingController(text: '0');
  String _delivery = 'SHIPPING';
  String? _invoiceId;
  String? _invoiceNumber;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _invoiceId = widget.invoiceId;
  }

  @override
  void dispose() {
    _company.dispose();
    _tracking.dispose();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _pickInvoice() async {
    final q = TextEditingController();
    List<dynamic> results = [];
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('فاتورة معتمدة للشحن',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: q,
                        decoration: const InputDecoration(
                            labelText: 'بحث برقم الفاتورة'))),
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () async {
                    results = await ref
                        .read(salesRepositoryProvider)
                        .list(
                            query: q.text,
                            status: 'APPROVED');
                    setS(() {});
                  },
                ),
              ]),
              for (final v in results)
                ListTile(
                  title: Text((v as dynamic).number as String,
                      textDirection: TextDirection.ltr),
                  onTap: () {
                    setState(() {
                      _invoiceId = (v as dynamic).id as String;
                      _invoiceNumber =
                          (v as dynamic).number as String;
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_invoiceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('اختر فاتورة معتمدة أولا.')));
      return;
    }
    if (_delivery == 'SHIPPING' &&
        (_name.text.trim().isEmpty ||
            _phone.text.trim().isEmpty ||
            _address.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'الشحن يتطلب اسم المستلم والهاتف والعنوان.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final id =
          await ref.read(shippingRepositoryProvider).create({
        'sales_invoice_id': _invoiceId,
        'shipping_company': _company.text.trim().isEmpty
            ? null
            : _company.text.trim(),
        'tracking_number': _tracking.text.trim().isEmpty
            ? null
            : _tracking.text.trim(),
        'recipient_name': _name.text.trim().isEmpty
            ? null
            : _name.text.trim(),
        'recipient_phone': _phone.text.trim().isEmpty
            ? null
            : _phone.text.trim(),
        'address': _address.text.trim().isEmpty
            ? null
            : _address.text.trim(),
        'city': _city.text.trim().isEmpty
            ? null
            : _city.text.trim(),
        'shipping_cost': double.tryParse(_cost.text) ?? 0,
        'delivery_method': _delivery,
        'status': 'PREPARING',
      });
      ref.invalidate(shipmentsPageProvider);
      if (mounted) {
        context.pushReplacement('/shipping/$id');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'حدث خطأ أثناء تنفيذ العملية.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
            body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(_invoiceNumber ?? 'فاتورة معتمدة *',
                textDirection: _invoiceNumber == null
                    ? TextDirection.rtl
                    : TextDirection.ltr),
            trailing: TextButton(
                onPressed: _pickInvoice,
                child: const Text('اختيار')),
          ),
          DropdownButtonFormField<String>(
            initialValue: _delivery,
            decoration:
                const InputDecoration(labelText: 'التوصيل'),
            items: const [
              DropdownMenuItem(
                  value: 'OFFICE_PICKUP',
                  child: Text('استلام من الفرع')),
              DropdownMenuItem(
                  value: 'SHIPPING', child: Text('شحن')),
            ],
            onChanged: (v) =>
                setState(() => _delivery = v ?? 'SHIPPING'),
          ),
          TextField(
              controller: _company,
              decoration: const InputDecoration(
                  labelText: 'شركة الشحن')),
          TextField(
              controller: _tracking,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                  labelText: 'رقم التتبع')),
          TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'اسم المستلم * للشحن')),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'هاتف المستلم * للشحن')),
          TextField(
              controller: _address,
              decoration: const InputDecoration(
                  labelText: 'العنوان * للشحن')),
          TextField(
              controller: _city,
              decoration:
                  const InputDecoration(labelText: 'المدينة')),
          TextField(
              controller: _cost,
              keyboardType:
                  const TextInputType.numberWithOptions(
                      decimal: true),
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                  labelText: 'تكلفة الشحن')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2))
                : const Text('إنشاء الشحنة'),
          ),
        ],
      ),
    );
  }
}
