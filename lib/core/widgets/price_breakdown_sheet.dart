import 'package:flutter/material.dart';

import 'package:muevex/core/services/price_calculator.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/utils/money.dart';

const Map<String, String> _serviceTypeLabels = {
  'muebles': 'Muebles',
  'electrodomesticos': 'Electrodomésticos',
  'cajas': 'Cajas',
  'piso': 'Mudanza de piso',
};

const Map<String, String> _hourPeriodLabels = {
  'early_morning': 'Madrugada (6–9 AM)',
  'morning': 'Mañana (9 AM–12 PM)',
  'afternoon': 'Tarde (12–6 PM)',
  'evening': 'Noche (6–9 PM)',
  'night': 'Madrugada (9 PM–6 AM)',
};

/// Muestra el desglose itemizado del precio estimado, para que el usuario
/// entienda de qué se compone la tarifa (transparencia de precios).
Future<void> showPriceBreakdownSheet(
  BuildContext context, {
  required double distanceKm,
  required String serviceType,
  required bool needsHelp,
  required int floors,
  String? hourPeriod,
}) {
  final typeMultiplier = PriceCalculator
          .serviceTypeMultipliers[serviceType] ??
      1.0;
  final distanceCost = distanceKm * PriceCalculator.pricePerKm;
  final floorsCost = floors * PriceCalculator.floorsFeePerFloor;
  final total = PriceCalculator.calculateRecommendedPrice(
    distanceKm: distanceKm,
    serviceType: serviceType,
    needsHelp: needsHelp,
    floors: floors,
    hourPeriod: hourPeriod,
  );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(sheetContext),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Desglose del precio',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Así se calcula tu tarifa estimada',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 18),
            _BreakdownRow(
              label: 'Tarifa base',
              amount: money(PriceCalculator.baseFare),
            ),
            _BreakdownRow(
              label: 'Distancia (${distanceKm.toStringAsFixed(1)} km × '
                  '\$2.000)',
              amount: money(distanceCost),
            ),
            _BreakdownRow(
              label: 'Tipo de carga · '
                  '${_serviceTypeLabels[serviceType] ?? 'Carga'}',
              amount: '×${typeMultiplier.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}',
            ),
            if (needsHelp)
              _BreakdownRow(
                label: 'Ayuda de carga',
                amount: money(PriceCalculator.helpLoadFee),
              ),
            if (floors > 0)
              _BreakdownRow(
                label: '$floors piso${floors > 1 ? 's' : ''} (× '
                    '\$2.000)',
                amount: money(floorsCost),
              ),
            if (hourPeriod != null &&
                PriceCalculator.hourMultipliers.containsKey(hourPeriod))
              _BreakdownRow(
                label: 'Factor horario · '
                    '${_hourPeriodLabels[hourPeriod] ?? hourPeriod}',
                amount:
                    '×${PriceCalculator.hourMultipliers[hourPeriod]!.toStringAsFixed(1)}',
              ),
            const Divider(height: 28),
            _BreakdownRow(
              label: 'Total estimado',
              amount: money(total),
              isTotal: true,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MuevexTheme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: MuevexTheme.accentColor),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Precio estimado. El conductor confirma el valor '
                      'final antes de iniciar el viaje.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF334155)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String amount;
  final bool isTotal;

  const _BreakdownRow({
    required this.label,
    required this.amount,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: isTotal ? 15 : 13.5,
      fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
      color: isTotal ? const Color(0xFF111827) : Colors.grey.shade700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(label, style: labelStyle),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: isTotal ? 20 : 14,
              fontWeight: FontWeight.w800,
              color: isTotal
                  ? MuevexTheme.secondaryColor
                  : const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}