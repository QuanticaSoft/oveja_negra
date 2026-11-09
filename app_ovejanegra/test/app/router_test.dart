import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ovejanegra/app/destinations.dart';
import 'package:ovejanegra/app/router.dart';
import 'package:ovejanegra/features/auth/domain/auth_user.dart';

AuthUser user(List<String> permissions) =>
    AuthUser(id: 1, username: 'u', fullName: 'U', role: 'X', permissions: {...permissions});

void main() {
  final cashier = user(['catalog.read', 'products.availability', 'orders.create', 'orders.read', 'payments.create']);
  final manager = user(['catalog.read', 'purchases.read', 'ingredients.read', 'expenses.read', 'dashboard.read', 'reports.read']);

  test('el menú muestra solo las secciones permitidas, en orden', () {
    expect(destinationsFor(cashier).map((d) => d.label), ['Nueva venta', 'Pedidos', 'Cartilla']);
    expect(destinationsFor(manager).map((d) => d.label),
        ['Dashboard', 'Cartilla', 'Compras', 'Insumos e inventario', 'Gastos', 'Reportes']);
    expect(homeFor(cashier), '/sales/new');
    expect(homeFor(user([])), accountPath);
  });

  test('redirección según la sesión y los permisos', () {
    const loading = AsyncLoading<AuthUser?>();
    expect(redirectFor(loading, '/orders'), '/splash');
    expect(redirectFor(loading, '/splash'), isNull);
    expect(redirectFor(AsyncError<AuthUser?>(Exception('sin red'), StackTrace.empty), '/orders'), '/splash');

    const loggedOut = AsyncData<AuthUser?>(null);
    expect(redirectFor(loggedOut, '/orders'), '/login');
    expect(redirectFor(loggedOut, '/login'), isNull);

    final cashierSession = AsyncData<AuthUser?>(cashier);
    expect(redirectFor(cashierSession, '/login'), '/sales/new');
    expect(redirectFor(cashierSession, '/splash'), '/sales/new');
    expect(redirectFor(cashierSession, '/orders'), isNull);
    expect(redirectFor(cashierSession, '/orders/15'), isNull);
    // Sin permiso: vuelve a su inicio aunque escriba la ruta.
    expect(redirectFor(cashierSession, '/users'), '/sales/new');
    expect(redirectFor(cashierSession, '/dashboard'), '/sales/new');
    expect(redirectFor(cashierSession, accountPath), isNull);
  });
}
