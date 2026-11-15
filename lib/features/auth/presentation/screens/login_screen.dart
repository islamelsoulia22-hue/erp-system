import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/backend_mode.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/local/password_hash.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // نسخة الجهاز: حساب المدير الافتراضي مكتوب جاهز —
    // المستخدم يضغط (دخول) فقط.
    if (resolveBackendMode() == BackendMode.local) {
      _email.text = 'admin@local';
      _password.text = kDefaultAdminPassword;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _errorMessage(Object e) {
    if (e is AppFailure) return e.messageAr;
    return 'حدث خطأ أثناء تنفيذ العملية، برجاء المحاولة مرة أخرى.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final ok = await ref
        .read(loginControllerProvider.notifier)
        .login(email: _email.text, password: _password.text);
    if (!mounted) return;
    if (!ok) {
      final err = ref.read(loginControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(err ?? const UnknownFailure()))),
      );
    }
    // On success router redirect handles navigation (no manual push).
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginControllerProvider);
    final loading = loginState.isLoading;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.mdx),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: BrandLogo(size: 88, radius: 20),
                ),
                const SizedBox(
                    height: AppSpacing.mdx),
                Text(
                  'SANAD — سند',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium,
                ),
                Text(
                  'نظام سند — سجل الدخول للمتابعة',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall,
                ),
                const SizedBox(
                    height: AppSpacing.mdx),
                AppCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType
                              .emailAddress,
                          textDirection:
                              TextDirection.ltr,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'البريد الإلكتروني',
                            prefixIcon: Icon(Icons
                                .email_outlined),
                          ),
                          validator: (v) {
                            if (v == null ||
                                v.trim().isEmpty) {
                              return 'البريد الإلكتروني مطلوب';
                            }
                            return Validators.email(
                                v.trim());
                          },
                        ),
                        const SizedBox(
                            height: AppSpacing.md),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textDirection:
                              TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            prefixIcon: const Icon(
                                Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() =>
                                      _obscure =
                                          !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons
                                        .visibility_outlined
                                    : Icons
                                        .visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator:
                              Validators.required,
                          onFieldSubmitted: (_) =>
                              _submit(),
                        ),
                        const SizedBox(
                            height: AppSpacing.mdx),
                        FilledButton(
                          onPressed:
                              loading ? null : _submit,
                          child: loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(
                                          strokeWidth:
                                              2,
                                          color: Colors
                                              .white),
                                )
                              : const Text('دخول'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
