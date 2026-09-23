import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muevex/features/customer/providers/customer_providers.dart';
import 'package:muevex/features/service/providers/service_providers.dart';

/// Invalida todos los providers keep-alive tras el logout para que una
/// proxima sesion no arrastre datos (servicios, formulario, mapa) del
/// usuario anterior.
void invalidateSessionProviders(WidgetRef ref) {
  ref.invalidate(customerProfileProvider);
  ref.invalidate(customerServiceStatusProvider);
  ref.invalidate(serviceFormProvider);
  ref.invalidate(currentServiceProvider);
  ref.invalidate(userServicesProvider);
  ref.invalidate(recommendedDistanceKmProvider);
  ref.invalidate(recommendedPriceProvider);
}
