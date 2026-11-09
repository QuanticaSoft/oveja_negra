import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/api_error_text.dart';
import 'session_controller.dart';

/// Datos de la sesión, cambio de la contraseña propia y cierre de sesión.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).value;
    if (user == null) {
      return const SizedBox.shrink();
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(user.fullName),
            subtitle: Text('${user.username} · ${user.role}'),
          ),
        ),
        const SizedBox(height: 16),
        const _ChangePasswordCard(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('account.logout'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => ref.read(sessionControllerProvider.notifier).logout(),
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}

class _ChangePasswordCard extends ConsumerStatefulWidget {
  const _ChangePasswordCard();

  @override
  ConsumerState<_ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends ConsumerState<_ChangePasswordCard> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Mismas reglas que el backend: 8 a 72 caracteres (límite de bcrypt).
  static String? validateNewPassword(String? value) {
    if (value == null || value.length < 8) {
      return 'Mínimo 8 caracteres.';
    }
    if (value.length > 72) {
      return 'Máximo 72 caracteres.';
    }
    return null;
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
      await ref.read(sessionControllerProvider.notifier).changePassword(_current.text, _next.text);
      _form.currentState!.reset();
      for (final c in [_current, _next, _confirm]) {
        c.clear();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña cambiada. Las demás sesiones se cerraron.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.fieldError('new_password') ?? e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cambiar contraseña', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
              TextFormField(
                controller: _current,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña actual'),
                validator: (v) => (v == null || v.isEmpty) ? 'Requerida.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña nueva'),
                validator: validateNewPassword,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repite la contraseña nueva'),
                validator: (v) => v != _next.text ? 'No coincide.' : null,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
