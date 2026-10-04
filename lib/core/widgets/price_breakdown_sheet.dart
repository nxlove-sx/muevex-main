import 'package:flutter/material.dart';

import 'package:muevex/core/services/tariff_engine.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/utils/money.dart';

/// Muestra el desglose itemizado del precio estimado.
///
/// Acepta la **[Tarifa] ya calculada**, no una `TarifaEntrada`, a propósito.
///
/// Cada pantalla calculaba su tarifa dos veces: una para el precio que muestra
/// y otra para el desglose, reconstruyendo la entrada a mano. Las dos entradas
/// no tienen por qué coincidir: la del desglose usaba solo los artículos del
/// formulario, sin el respaldo al tipo de carga que sí hace el precio. Con la
/// carga inicial (artículos vacíos) eso hacía que un servicio de muebles se
/// cotizara en $55.000 y el desglose dijera $25.000.
///
/// Pasando la tarifa ya calculada no hay dos verdades: quien pinta el desglose
/// pinta exactamente lo mismo que pinta el precio.
Future<void> showPriceBreakdownSheet(
  BuildContext context, {
  required Tarifa tarifa,
}) async {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(sheetContext),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
            ...tarifa.lineas.map((linea) => _BreakdownRow(
                  label: linea.concepto,
                  amount: money(linea.monto),
                  detalle: linea.detalle,
                )),
            const Divider(height: 28),
            // Los precios de la tabla TRANSPERSQUI son NETOS. Se lo decimos al
            // cliente antes de que lo descubra en la factura: el total que va
            // a pagar lleva el IVA encima. Ver migracion_facturacion_v4.sql.
            _BreakdownRow(
              label: 'Subtotal (sin IVA)',
              amount: money(tarifa.total),
            ),
            _BreakdownRow(
              label: 'IVA (19%)',
              amount: money(tarifa.total * ivaRate),
            ),
            _BreakdownRow(
              label: 'Total a pagar',
              amount: moneyConIva(tarifa.total),
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
                      'Precio estimado según tabla TRANSPERSQUI. El IVA se suma '
                      'encima del subtotal, por eso el total es mayor. El conductor '
                      'confirma el valor final antes de iniciar el viaje.',
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

/// Helper para crear la entrada desde el formulario legacy (compatibilidad).
///
/// Útil mientras se migra la UI al selector de artículos.
TarifaEntrada entradaDesdeFormularioLegacy({
  required double distanceKm,
  required String serviceType,
  required bool needsHelp,
  required int floors,
  String? hourPeriod,
}) {
  final articulos = _articulosPorTipoCargaLegacy(serviceType);
  return TarifaEntrada(
    distanciaKm: distanceKm,
    articulos: articulos,
    pisosRecogida: 0,
    pisosEntrega: floors,
    ayudante: needsHelp ? OrigenAyudante.plataforma : OrigenAyudante.incluido,
    viajes: 1,
  );
}

List<ArticuloSeleccionado> _articulosPorTipoCargaLegacy(String? loadType) {
  switch (loadType) {
    case 'muebles':
      return [ArticuloSeleccionado(TarifaEngine.articuloPorId('sofa_3')!)];
    case 'electrodomesticos':
      return [ArticuloSeleccionado(TarifaEngine.articuloPorId('lavadora')!)];
    case 'piso':
      return [
        ArticuloSeleccionado(TarifaEngine.articuloPorId('colchon_doble')!),
        ArticuloSeleccionado(TarifaEngine.articuloPorId('closet_desarmado')!),
      ];
    case 'cajas':
    default:
      return const [];
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String amount;
  final String? detalle;
  final bool isTotal;

  const _BreakdownRow({
    required this.label,
    required this.amount,
    this.detalle,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: isTotal ? 15 : 13.5,
      fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
      color: isTotal ? const Color(0xFF111827) : Colors.grey.shade700,
    );
    final children = <Widget>[
      Row(
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
    ];
    if (detalle != null && detalle!.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 2),
        Text(
          detalle!,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
