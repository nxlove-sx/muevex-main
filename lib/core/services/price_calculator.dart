/// Motor de cálculo de precio recomendado para MUEVEX
class PriceCalculator {
  // Tarifa base del servicio
  static const double baseFare = 5000.0; // $5.000

  // Precio por kilómetro
  static const double pricePerKm = 2000.0; // $2.000 por km

  // Cargos adicionales
  static const double helpLoadFee = 5000.0; // $5.000 ayuda para cargar
  static const double helpUnloadFee = 3000.0; // $3.000 ayuda para descargar
  static const double floorsFeePerFloor = 2000.0; // $2.000 por piso/escalera

  // Factores de horario y demanda
  static const Map<String, double> hourMultipliers = {
    'early_morning': 1.2, // 6-9 AM
    'morning': 1.0, // 9-12 PM
    'afternoon': 0.95, // 12-6 PM
    'evening': 1.1, // 6-9 PM
    'night': 1.3, // 9 PM - 6 AM
  };

  // Factores por tipo de servicio
  static const Map<String, double> serviceTypeMultipliers = {
    'muebles': 1.0,
    'electrodomesticos': 1.15,
    'cajas': 0.9,
    'piso': 1.2,
  };

  // Calcular precio recomendado
  static double calculateRecommendedPrice({
    required double distanceKm,
    required String serviceType,
    required bool needsHelp,
    required int floors,
    String?
        hourPeriod, // 'early_morning', 'morning', 'afternoon', 'evening', 'night'
  }) {
    // 1. Tarifa base
    double price = baseFare;

    // 2. Distancia
    price += distanceKm * pricePerKm;

    // 3. Tipo de servicio
    final typeMultiplier = serviceTypeMultipliers[serviceType] ?? 1.0;
    price *= typeMultiplier;

    // 4. Ayuda para cargar
    if (needsHelp) {
      price += helpLoadFee;
    }

    // 5. Ayuda para descargar (asumimos ayuda en la mitad de los casos o 0 si no)
    // En un caso completo: + helpUnloadFee, pero para el precio recomendado inicial
    // solo cobramos ayuda de carga según el specification

    // 6. Pisos/escaleras
    price += floors * floorsFeePerFloor;

    // 7. Factor de horario/momento
    if (hourPeriod != null && hourMultipliers.containsKey(hourPeriod)) {
      price *= hourMultipliers[hourPeriod]!;
    }

    // Redondear a nearest 1000
    return (price / 1000).round() * 1000;
  }

  /// Generar descripción del precio
  static String generatePriceBreakdown({
    required double distanceKm,
    required String serviceType,
    required bool needsHelp,
    required int floors,
    String? hourPeriod,
  }) {
    final parts = <String>[];

    // Tarifa base
    parts.add('Tarifa base: ${baseFare.toStringAsFixed(0)}');

    // Distancia
    final distanceCost = distanceKm * pricePerKm;
    parts.add('Distancia ($distanceKm km): ${distanceCost.toStringAsFixed(0)}');

    // Tipo de servicio
    final typeMultiplier = serviceTypeMultipliers[serviceType] ?? 1.0;
    final typeName = serviceTypeMultipliers.keys.firstWhere(
      (key) => serviceTypeMultipliers[key] == typeMultiplier,
      orElse: () => 'muebles',
    );
    parts.add(
        'Tipo servicio ($typeName): ${(baseFare * typeMultiplier).toStringAsFixed(0)}');

    // Ayuda de carga
    if (needsHelp) {
      parts.add('Ayuda carga: ${helpLoadFee.toStringAsFixed(0)}');
    }

    // Pisos
    if (floors > 0) {
      parts.add(
          '$floors pisos: ${(floors * floorsFeePerFloor).toStringAsFixed(0)}');
    }

    // Horario
    if (hourPeriod != null && hourMultipliers.containsKey(hourPeriod)) {
      final multiplier = hourMultipliers[hourPeriod]!;
      final hourlyText =
          multiplier > 1.0 ? 'aumento horario' : 'descuento horario';
      parts.add('$hourlyText ($hourPeriod): x$multiplier');
    }

    // Precio total
    final total = calculateRecommendedPrice(
      distanceKm: distanceKm,
      serviceType: serviceType,
      needsHelp: needsHelp,
      floors: floors,
      hourPeriod: hourPeriod,
    );
    parts.add('-----');
    parts.add('Precio recomendado: ${total.toStringAsFixed(0)}');

    return parts.join('\n');
  }
}
