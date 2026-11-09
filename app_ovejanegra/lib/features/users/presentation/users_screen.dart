import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/api_error_text.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/users_api.dart';
import '../domain/users.dart';

final usersApiProvider = Provider<UsersApi>((ref) => UsersApi(ref.watch(apiDioProvider)));
final usersProvider = FutureProvider.autoDispose<List<AppUser>>((ref) => ref.watch(usersApiProvider).users());
final rolesProvider = FutureProvider.autoDispose<List<Role>>((ref) => ref.watch(usersApiProvider).roles());
final permissionsProvider = FutureProvider.autoDispose<List<Permission>>((ref) => ref.watch(usersApiProvider).permissions());

/// Los roles son datos fijos de la BD (no hay API para crearlos); listarlos con detalle exige `roles.manage`.
const roleCodes = ['ADMIN', 'CAJERO', 'ENCARGADO'];

/// Mensajes claros para las protecciones del backend sobre usuarios y roles.
String userErrorMessage(ApiException e) => switch (e.code) {
      'LAST_ADMIN' => 'Debe quedar al menos un ADMIN activo.',
      'CANNOT_DEACTIVATE_SELF' => 'No puedes desactivar tu propia cuenta.',
      'CANNOT_CHANGE_OWN_ROLE' => 'No puedes cambiar tu propio rol.',
      'ADMIN_PERMISSIONS_REQUIRED' => 'El rol ADMIN debe conservar la administración de usuarios y de roles.',
      _ => e.fieldError('password') ?? e.fieldError('new_password') ?? e.fieldError('phone') ?? e.fieldError('username') ?? e.message,
    };

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canRoles = ref.watch(sessionControllerProvider).value?.can('roles.manage') ?? false;
    if (!canRoles) {
      return const _UsersTab();
    }
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Usuarios'), Tab(text: 'Permisos por rol')]),
        Expanded(child: TabBarView(children: [_UsersTab(), _RolesTab()])),
      ]),
    );
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  Future<void> _call(BuildContext context, WidgetRef ref, Future<void> Function() action, String success) async {
    try {
      await action();
      ref.invalidate(usersProvider);
      if (context.mounted) {
        showMessage(context, success);
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        showMessage(context, userErrorMessage(e));
      }
    }
  }

  Future<void> _resetPassword(BuildContext context, WidgetRef ref, AppUser user) async {
    final password = await showDialog<String>(context: context, builder: (_) => _PasswordDialog(user: user));
    if (password != null && context.mounted) {
      await _call(context, ref, () => ref.read(usersApiProvider).resetPassword(user.id, password),
          'Contraseña restablecida. Sus sesiones abiertas se cerraron.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionControllerProvider).value!;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('users.new'),
        onPressed: () => showDialog<void>(context: context, builder: (_) => const UserDialog()),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Usuario'),
      ),
      body: AsyncView(
        value: ref.watch(usersProvider),
        onRetry: () => ref.invalidate(usersProvider),
        builder: (users) => ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
          for (final u in users)
            Card(
              child: ListTile(
                key: Key('user.${u.id}'),
                leading: CircleAvatar(
                  backgroundColor: u.isActive ? AppColors.orange : const Color(0xFFE0E0E0),
                  child: Text(u.fullName.characters.first, style: const TextStyle(color: AppColors.black)),
                ),
                title: Text('${u.fullName}${u.id == me.id ? ' (tú)' : ''}',
                    style: TextStyle(decoration: u.isActive ? null : TextDecoration.lineThrough)),
                subtitle: Text([
                  u.username,
                  u.role,
                  if (u.phone != null) u.phone!,
                  u.lastLoginAt == null ? 'nunca ingresó' : 'último ingreso ${LaPaz.dateTime(u.lastLoginAt!)}',
                ].join(' · ')),
                trailing: PopupMenuButton<String>(
                  key: Key('user.menu.${u.id}'),
                  onSelected: (action) => switch (action) {
                    'edit' => showDialog<void>(context: context, builder: (_) => UserDialog(user: u)),
                    'password' => _resetPassword(context, ref, u),
                    _ => _call(context, ref, () => ref.read(usersApiProvider).setActive(u.id, !u.isActive),
                        u.isActive ? 'Usuario desactivado; sus sesiones se cerraron.' : 'Usuario activado.'),
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Editar')),
                    const PopupMenuItem(value: 'password', child: Text('Restablecer contraseña')),
                    PopupMenuItem(value: 'status', key: Key('user.status.${u.id}'), child: Text(u.isActive ? 'Desactivar' : 'Activar')),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Alta (sin [user]) o edición de un usuario.
class UserDialog extends ConsumerStatefulWidget {
  const UserDialog({super.key, this.user});

  final AppUser? user;

  @override
  ConsumerState<UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<UserDialog> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.user?.username);
  late final _fullName = TextEditingController(text: widget.user?.fullName);
  late final _phone = TextEditingController(text: widget.user?.phone);
  final _password = TextEditingController();
  late String _role = widget.user?.role ?? 'CAJERO';
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.user == null;

  @override
  void dispose() {
    for (final c in [_username, _fullName, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
    try {
      final api = ref.read(usersApiProvider);
      if (_isNew) {
        await api.create({
          'username': _username.text.trim(),
          'full_name': _fullName.text.trim(),
          'phone': phone,
          'role_code': _role,
          'password': _password.text,
        });
      } else {
        await api.update(widget.user!.id, {
          'full_name': _fullName.text.trim(),
          'phone': phone,
          if (_role != widget.user!.role) 'role_code': _role,
        });
      }
      ref.invalidate(usersProvider);
      if (mounted) {
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      setState(() => _error = userErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Nuevo usuario' : 'Editar ${widget.user!.username}'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
              if (_isNew)
                TextFormField(
                  key: const Key('user.username'),
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Usuario', helperText: 'Minúsculas, números, punto, guion (3 a 40)'),
                  validator: (v) => RegExp(r'^[a-z0-9._-]{3,40}$').hasMatch((v ?? '').trim().toLowerCase()) ? null : 'Usuario inválido.',
                ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('user.fullName'),
                controller: _fullName,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido.' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Celular (opcional)', hintText: '+59170000000'),
                validator: (v) => v == null || v.trim().isEmpty || RegExp(r'^\+591\d{8}$').hasMatch(v.trim()) ? null : 'Formato +591 y 8 dígitos.',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: [for (final r in roleCodes) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => setState(() => _role = v!),
              ),
              if (_isNew) ...[
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('user.password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña inicial', helperText: '8 a 72 caracteres'),
                  validator: (v) => (v == null || v.length < 8 || v.length > 72) ? 'Entre 8 y 72 caracteres.' : null,
                ),
              ],
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          key: const Key('user.save'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.user});

  final AppUser user;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Nueva contraseña para ${widget.user.username}'),
        content: Form(
          key: _form,
          child: TextFormField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Contraseña nueva', helperText: 'Entrégala en persona; nunca por chat.'),
            validator: (v) => (v == null || v.length < 8 || v.length > 72) ? 'Entre 8 y 72 caracteres.' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, _password.text);
              }
            },
            child: const Text('Restablecer'),
          ),
        ],
      );
}

/// Matriz de permisos de un rol. Guardar reemplaza el conjunto completo y rige al instante.
class _RolesTab extends ConsumerStatefulWidget {
  const _RolesTab();

  @override
  ConsumerState<_RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends ConsumerState<_RolesTab> {
  int? _roleId;
  Set<String>? _draft;
  bool _saving = false;

  Future<void> _save(Role role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Guardar permisos de ${role.code}'),
        content: const Text('El cambio rige al instante para todos los usuarios con este rol.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(
            key: const Key('roles.confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(usersApiProvider).replacePermissions(role.id, _draft!);
      ref.invalidate(rolesProvider);
      if (ref.read(sessionControllerProvider).value?.role == role.code) {
        await ref.read(sessionControllerProvider.notifier).reloadUser();
      }
      setState(() => _draft = null);
      if (mounted) {
        showMessage(context, 'Permisos guardados.');
      }
    } on ApiException catch (e) {
      if (mounted) {
        showMessage(context, userErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView(
      value: ref.watch(rolesProvider),
      onRetry: () => ref.invalidate(rolesProvider),
      builder: (roles) => AsyncView(
        value: ref.watch(permissionsProvider),
        onRetry: () => ref.invalidate(permissionsProvider),
        builder: (permissions) {
          final role = roles.firstWhere((r) => r.id == _roleId, orElse: () => roles.first);
          final draft = _draft ?? role.permissions;
          final modules = <String, List<Permission>>{};
          for (final p in permissions) {
            (modules[p.module] ??= []).add(p);
          }
          return Column(children: [
            SizedBox(
              height: 56,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
                for (final r in roles)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('roles.${r.code}'),
                      label: Text(r.code),
                      selected: r.id == role.id,
                      onSelected: (_) => setState(() {
                        _roleId = r.id;
                        _draft = null;
                      }),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final MapEntry(key: module, value: list) in modules.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Text(module.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.grey)),
                  ),
                  for (final p in list)
                    CheckboxListTile(
                      key: Key('perm.${p.code}'),
                      dense: true,
                      value: draft.contains(p.code),
                      title: Text(p.description),
                      subtitle: Text(p.code),
                      // El ADMIN conserva siempre la administración (el backend lo exige).
                      onChanged: role.code == 'ADMIN' && Role.adminRequired.contains(p.code)
                          ? null
                          : (on) => setState(() => _draft = on! ? {...draft, p.code} : ({...draft}..remove(p.code))),
                    ),
                ],
              ]),
            ),
            if (_draft != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  key: const Key('roles.save'),
                  onPressed: _saving ? null : () => _save(role),
                  child: Text('Guardar permisos de ${role.code}'),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
