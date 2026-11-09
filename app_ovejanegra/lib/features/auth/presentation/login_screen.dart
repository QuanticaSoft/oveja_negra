import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/api_error_text.dart';
import 'session_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).login(_identifier.text.trim(), _password.text);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final endedReason = ref.read(sessionControllerProvider.notifier).endedReason;
    final message = _error ?? endedReason;
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const BrandMark(fontSize: 34),
                  const SizedBox(height: 8),
                  const Text('Hamburguesería', style: TextStyle(color: AppColors.grey)),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _form,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Ingresar', style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 16),
                              if (message != null) ...[ErrorBanner(message), const SizedBox(height: 16)],
                              TextFormField(
                                key: const Key('login.identifier'),
                                controller: _identifier,
                                decoration: const InputDecoration(labelText: 'Usuario o celular', prefixIcon: Icon(Icons.person_outline)),
                                autofillHints: const [AutofillHints.username],
                                textInputAction: TextInputAction.next,
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu usuario o celular.' : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const Key('login.password'),
                                controller: _password,
                                obscureText: _obscure,
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                autofillHints: const [AutofillHints.password],
                                onFieldSubmitted: (_) => _submit(),
                                validator: (v) => (v == null || v.isEmpty) ? 'Ingresa tu contraseña.' : null,
                              ),
                              const SizedBox(height: 24),
                              FilledButton(
                                key: const Key('login.submit'),
                                onPressed: _submitting ? null : _submit,
                                child: _submitting
                                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                                    : const Text('Ingresar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
