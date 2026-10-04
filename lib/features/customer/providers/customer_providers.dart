import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:muevex/core/models/customer_profile_model.dart';
import 'package:muevex/core/models/service_model.dart';
import 'package:muevex/core/models/invoice_model.dart';
import 'package:muevex/features/auth/providers/auth_provider.dart';
import 'package:muevex/core/supabase/supabase_client.dart';

// Customer profile provider
final customerProfileProvider = FutureProvider<CustomerProfile?>((ref) async {
  final user = ref.watch(authProvider).value;
  if (user != null) {
    try {
      return await getCustomerProfile(user.id);
    } catch (e) {
      return null;
    }
  }
  return null;
});

// Services provider - TODOS los servicios del cliente (actuales y anteriores).
// La home separa en "Mis servicios" (pendientes + activos con conductor) y
// "Servicios anteriores" (completados/cancelados). RLS ya restringe a
// customer_id = auth.uid().
final customerServicesProvider = FutureProvider<List<Service>>((ref) async {
  final user = ref.watch(authProvider).value;
  if (user == null) return <Service>[];

  // Realtime sobre `services` del cliente: al asignarse un conductor (o
  // cambiar estado) la lista se refresca sola y el cliente ve la tarjeta del
  // conductor sin reabrir la app.
  final channel = supabase
      .channel('customer-services-list:${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'services',
        filter: PostgresChangeFilter(
          column: 'customer_id',
          type: PostgresChangeFilterType.eq,
          value: user.id,
        ),
        callback: (payload) {
          debugPrint(
              'MUEVEX realtime services: event=${payload.eventType} newRecord=${payload.newRecord['id']} status=${payload.newRecord['status']} driver_id=${payload.newRecord['driver_id']}');
          HapticFeedback.mediumImpact();
          ref.invalidateSelf();
        },
      )
      .subscribe();
  ref.onDispose(channel.unsubscribe);

  return getUserServices(user.id);
});

/// Facturas emitidas del cliente actual, indexadas por `service_id`.
///
/// Se carga una sola vez y se reparte entre las tarjetas: el historial llega a
/// tener decenas de servicios y consultar las facturas una por una desde cada
/// tarjeta era una petición por fila.
///
/// Solo se guardan las **emitidas**: una minifactura en borrador todavía no se
/// puede enseñar, así que no debe ofrecer un botón que no lleva a ninguna
/// parte. Publicar la minifactura es justo el paso que la pasa a `emitida`.
final myInvoicesByServiceProvider =
    FutureProvider<Map<String, Invoice>>((ref) async {
  final user = ref.watch(authProvider).value;
  if (user == null) return <String, Invoice>{};

  final invoices = await getMyInvoices(status: InvoiceStatus.emitida);
  return {for (final inv in invoices) inv.serviceId: inv};
});

// Current service provider - servicio activo
final currentCustomerServiceProvider = StateProvider<Service?>((ref) => null);

// Price provider - precio recomendado
final customerPriceProvider = StateProvider<double>((ref) => 0.0);

// Service status provider para cliente
final customerServiceStatusProvider =
    StateNotifierProvider<CustomerServiceStatusNotifier, ServiceStatus>(
  (ref) => CustomerServiceStatusNotifier(),
);

class CustomerServiceStatusNotifier extends StateNotifier<ServiceStatus> {
  CustomerServiceStatusNotifier() : super(ServiceStatus.solicitado);

  void setStatus(ServiceStatus newStatus) {
    state = newStatus;
  }
}

// Selected locations
final selectedOriginProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);
final selectedDestinationProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

// Nearby drivers provider
final nearbyDriversProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return <Map<String, dynamic>>[];
});
