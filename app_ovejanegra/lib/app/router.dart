import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/auth_user.dart';
import '../features/auth/presentation/account_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/catalog/presentation/menu_screen.dart';
import '../features/catalog/presentation/product_form_screen.dart';
import '../features/catalog/presentation/products_screen.dart';
import '../features/home/presentation/coming_soon_screen.dart';
import '../features/orders/presentation/edit_items_screen.dart';
import '../features/orders/presentation/new_sale_screen.dart';
import '../features/orders/presentation/order_detail_screen.dart';
import '../features/orders/presentation/orders_screen.dart';
import 'destinations.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // go_router vuelve a evaluar `redirect` cada vez que cambia la sesión.
  final session = ValueNotifier<AsyncValue<AuthUser?>>(ref.read(sessionControllerProvider));
  ref
    ..listen(sessionControllerProvider, (_, next) => session.value = next)
    ..onDispose(session.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: session,
    redirect: (context, state) => redirectFor(session.value, state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: accountPath, builder: (_, _) => const AccountScreen()),
          GoRoute(path: '/sales/new', builder: (_, _) => const NewSaleScreen()),
          GoRoute(
            path: '/orders',
            builder: (_, _) => const OrdersScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => OrderDetailScreen(orderId: _id(state)),
                routes: [GoRoute(path: 'items', builder: (_, state) => EditItemsScreen(orderId: _id(state)))],
              ),
            ],
          ),
          GoRoute(path: '/menu', builder: (_, _) => const MenuScreen()),
          GoRoute(
            path: '/products',
            builder: (_, _) => const ProductsScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, _) => const ProductFormScreen()),
              GoRoute(path: ':id', builder: (_, state) => ProductFormScreen(productId: _id(state))),
            ],
          ),
          for (final destination in destinations.where((d) => d.part != null))
            GoRoute(path: destination.path, builder: (_, _) => ComingSoonScreen(destination: destination)),
        ],
      ),
    ],
  );
});

int _id(GoRouterState state) => int.tryParse(state.pathParameters['id'] ?? '') ?? 0;

/// Separado del router para poder probarlo sin widgets.
String? redirectFor(AsyncValue<AuthUser?> session, String location) {
  if (!session.hasValue) {
    // Restaurando la sesión, o sin red al restaurarla: la pantalla de inicio muestra cuál.
    return location == '/splash' ? null : '/splash';
  }
  final user = session.value;
  if (user == null) {
    return location == '/login' ? null : '/login';
  }
  if (location == '/login' || location == '/splash' || location == '/') {
    return homeFor(user);
  }
  final destination = destinationAt(location);
  if (destination != null && !user.can(destination.permission)) {
    return homeFor(user);
  }
  return null;
}
