import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_auth.dart';
import 'password_hash.dart';

/// دخول النسخة اللوكال (إيميل + باسورد من قاعدة الجهاز).
class LocalLoginScreen extends ConsumerStatefulWidget {
  const LocalLoginScreen({super.key});

  @override
  ConsumerState<LocalLoginScreen> createState() => _LocalLoginScreenState();
}

class _LocalLoginScreenState extends ConsumerState<LocalLoginScreen> {
  final _email = TextEditingController(text: 'admin@local');
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(localAuthRepositoryProvider)
          .login(email: _email.text, password: _password.text);
      ref.invalidate(localSessionProvider);
    } on LocalAuthFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.messageAr)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر الدخول — حاول مجددا.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دخول — نسخة الجهاز')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.storage_outlined, size: 64, color: Colors.blue),
          const SizedBox(height: 16),
          const Text(
            'سند — نسخة الجهاز (بدون إنترنت)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'الإيميل',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'الباسورد',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('دخول'),
          ),
          const SizedBox(height: 12),
          Text(
            'أول تشغيل — الإيميل: admin@local والباسورد: $kDefaultAdminPassword',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
