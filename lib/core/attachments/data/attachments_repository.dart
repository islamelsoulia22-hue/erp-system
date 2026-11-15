import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';
import '../../backend/backend_mode.dart';
import '../../local/local_database.dart';
import '../../local/local_query.dart';
import '../../network/supabase_client.dart';

class Attachment {
  final String id;
  final String fileName;
  final String filePath;
  final DateTime createdAt;

  const Attachment({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.createdAt,
  });

  factory Attachment.fromMap(Map<String, dynamic> m) {
    return Attachment(
      id: m['id'] as String,
      fileName: (m['file_name'] as String?) ?? '',
      filePath: (m['file_path'] as String?) ?? '',
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class AttachmentsRepository {
  final dynamic _client;
  AttachmentsRepository(this._client);

  Future<List<Attachment>> list(
      String entityType, String entityId) async {
    try {
      final rows = (await _client
          .from('attachments')
          .select()
          .eq('entity_type', entityType)
          .eq('entity_id', entityId)
          .order('created_at', ascending: false)) as List;
      return rows
          .map((e) =>
              Attachment.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Uploads bytes to the private bucket and registers the row.
  Future<void> upload({
    required String entityType,
    required String entityId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    try {
      final safe = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path =
          '$entityType/$entityId/${DateTime.now().millisecondsSinceEpoch}_$safe';
      await _client.storage.from('attachments').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
                contentType: contentType,
                upsert: false),
          );
      await _client.from('attachments').insert({
        'entity_type': entityType,
        'entity_id': entityId,
        'file_name': fileName,
        'file_path': path,
        'file_type': contentType,
        'file_size': bytes.length,
        'uploaded_by': _client.auth.currentUser?.id,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> downloadUrl(String path) async {
    try {
      return await _client.storage
          .from('attachments')
          .createSignedUrl(path, 3600);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> remove(Attachment a) async {
    try {
      await _client.storage.from('attachments').remove([a.filePath]);
    } catch (_) {}
    try {
      await _client.from('attachments').delete().eq('id', a.id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final attachmentsRepositoryProvider =
    Provider<AttachmentsRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس — الملفات على الجهاز عبر storage المحلي.
  if (resolveBackendMode() == BackendMode.local) {
    return AttachmentsRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return AttachmentsRepository(ref.watch(supabaseClientProvider));
});

final attachmentsProvider = FutureProvider.autoDispose
    .family<List<Attachment>, ({String type, String id})>((ref, key) {
  return ref
      .watch(attachmentsRepositoryProvider)
      .list(key.type, key.id);
});
