import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/session_controller.dart';
import 'destinations.dart';
import 'theme.dart';

/// Marco de las pantallas con sesión. En tablet (≥ 900 px) el menú queda fijo a la izquierda; en
/// teléfono se abre desde el botón de la barra superior.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  static const wideBreakpoint = 900.0;

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).value;
    if (user == null) {
      return const SizedBox.shrink();
    }
    final items = destinationsFor(user);
    final current = destinationAt(location);
    final title = location == accountPath ? 'Mi cuenta' : current?.label ?? 'OVEJA_NEGRA';
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;

    Widget menu({required bool closeOnTap}) {
      final selected = location == accountPath ? items.length : items.indexWhere((d) => d == current);
      return NavigationDrawer(
        selectedIndex: selected < 0 ? null : selected,
        onDestinationSelected: (index) {
          if (closeOnTap) {
            Navigator.of(context).pop();
          }
          context.go(index < items.length ? items[index].path : accountPath);
        },
        children: [
          _MenuHeader(name: user.fullName, role: user.role),
          for (final d in items) NavigationDrawerDestination(icon: Icon(d.icon), label: Text(d.label)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8), child: Divider(color: Color(0xFF333333))),
          const NavigationDrawerDestination(icon: Icon(Icons.person_outline), label: Text('Mi cuenta')),
        ],
      );
    }

    final body = Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: !wide),
      drawer: wide ? null : menu(closeOnTap: true),
      body: SafeArea(child: child),
    );
    return wide ? Row(children: [menu(closeOnTap: false), Expanded(child: body)]) : body;
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.name, required this.role});

  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(),
          const SizedBox(height: 16),
          Text(name, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
          Text(role, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Nombre de la marca: "OVEJA" en blanco y "NEGRA" en naranja.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.fontSize = 22});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, letterSpacing: 1.5);
    return Text.rich(TextSpan(children: [
      TextSpan(text: 'OVEJA', style: style.copyWith(color: AppColors.white)),
      TextSpan(text: '_NEGRA', style: style.copyWith(color: AppColors.orange)),
    ]));
  }
}
