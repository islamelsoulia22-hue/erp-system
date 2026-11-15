import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/failures.dart';
import '../data/attachments_repository.dart';

/// Reusable attachments block for invoices, shipments, partners.
class AttachmentsSection extends ConsumerWidget {
  final String entityType;
  final String entityId;
  const AttachmentsSection(
      {super.key, required this.entityType, required this.entityId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list =
        ref.watch(attachmentsProvider((type: entityType, id: entityId)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('المرفقات',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _pick(context, ref, true),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('صورة'),
          ),
          TextButton.icon(
            onPressed: () => _pick(context, ref, false),
            icon: const Icon(Icons.attach_file_outlined),
            label: const Text('ملف'),
          ),
        ]),
        list.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('تعذر التحميل: $e'),
          data: (rows) {
            if (rows.isEmpty) {
              return const Text(
                  'لا توجد مرفقات — صور الفواتير والإيصالات هنا.');
            }
            return Column(
              children: [
                for (final a in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        const Icon(Icons.insert_drive_file_outlined),
                    title: Text(a.fileName),
                    trailing: IconButton(
                      icon:
                          const Icon(Icons.delete_outline),
                      onPressed: () async {
                        try {
                          await ref
                              .read(attachmentsRepositoryProvider)
                              .remove(a);
                          ref.invalidate(attachmentsProvider(
                              (type: entityType, id: entityId)));
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                    content: Text(e
                                            is AppFailure
                                        ? e.messageAr
                                        : 'حدث خطأ أثناء الحذف.')));
                          }
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pick(
      BuildContext context, WidgetRef ref, bool image) async {
    try {
      if (image) {
        final f = await ImagePicker()
            .pickImage(source: ImageSource.camera, imageQuality: 70);
        if (f == null) return;
        final bytes = await f.readAsBytes();
        await ref
            .read(attachmentsRepositoryProvider)
            .upload(
                entityType: entityType,
                entityId: entityId,
                fileName: f.name,
                bytes: bytes,
                contentType: 'image/jpeg');
      } else {
        final f = await FilePicker.pickFile();
        if (f == null) return;
        final bytes = await f.xFile.readAsBytes();
        await ref
            .read(attachmentsRepositoryProvider)
            .upload(
                entityType: entityType,
                entityId: entityId,
                fileName: f.name,
                bytes: bytes);
      }
      ref.invalidate(
          attachmentsProvider((type: entityType, id: entityId)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'حدث خطأ أثناء الرفع.')));
      }
    }
  }
}
