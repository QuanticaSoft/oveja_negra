import 'package:flutter/material.dart';

import '../features/auth/domain/auth_user.dart';

/// Secciones del menú. Cada una exige un permiso del backend; la app solo muestra las que el
/// usuario puede usar (el backend igual rechaza con 403 lo que no corresponda).
class Destination {
  const Destination(this.path, this.label, this.icon, this.permission, {this.part});

  final String path;
  final String label;
  final IconData icon;
  final String permission;

  /// Parte de la Fase 8 que implementa la pantalla (null = ya implementada).
  final String? part;
}

const destinations = <Destination>[
  Destination('/dashboard', 'Dashboard', Icons.space_dashboard_outlined, 'dashboard.read', part: '8d'),
  Destination('/sales/new', 'Nueva venta', Icons.point_of_sale_outlined, 'orders.create'),
  Destination('/orders', 'Pedidos', Icons.receipt_long_outlined, 'orders.read'),
  Destination('/menu', 'Cartilla', Icons.lunch_dining_outlined, 'catalog.read'),
  Destination('/products', 'Productos', Icons.inventory_2_outlined, 'catalog.manage'),
  Destination('/purchases', 'Compras', Icons.shopping_cart_outlined, 'purchases.read', part: '8c'),
  Destination('/inventory', 'Insumos e inventario', Icons.kitchen_outlined, 'ingredients.read', part: '8c'),
  Destination('/expenses', 'Gastos', Icons.payments_outlined, 'expenses.read', part: '8d'),
  Destination('/reports', 'Reportes', Icons.bar_chart_outlined, 'reports.read', part: '8d'),
  Destination('/users', 'Usuarios y permisos', Icons.manage_accounts_outlined, 'users.manage', part: '8d'),
];

const accountPath = '/account';

List<Destination> destinationsFor(AuthUser user) => [for (final d in destinations) if (user.can(d.permission)) d];

/// Primera sección permitida; si no tiene ninguna, su cuenta.
String homeFor(AuthUser user) {
  final allowed = destinationsFor(user);
  return allowed.isEmpty ? accountPath : allowed.first.path;
}

Destination? destinationAt(String location) {
  for (final d in destinations) {
    if (location == d.path || location.startsWith('${d.path}/')) {
      return d;
    }
  }
  return null;
}
