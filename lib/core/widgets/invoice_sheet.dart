import 'package:flutter/material.dart';

import 'package:muevex/core/models/invoice_model.dart';
import 'package:muevex/core/supabase/supabase_client.dart' as api;
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/utils/money.dart';

/// Abre la minifactura en una hoja inferior.
///
/// [invoiceId] es el identificador de la factura, no del servicio. Se usa el id
/// de la factura porque es lo único que sabe la lista de servicios: ahí lo que
/// se tiene es el `service_id`, y una factura siempre tiene
/// `invoices.service_id`.
///
/// La minifactura no se descarga ni se genera: todo lo que se ve sale de la fila
/// de `invoices` y de sus renglones. Por eso no hay botón de PDF, ni botón de
/// compartir, ni nada que dependa de Storage.
Future<void> showInvoiceSheet(
  BuildContext context, {
  required String invoiceId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InvoiceSheet(invoiceId: invoiceId),
  );
}

class _InvoiceSheet extends StatefulWidget {
  const _InvoiceSheet({required this.invoiceId});

  final String invoiceId;

  @override
  State<_InvoiceSheet> createState() => _InvoiceSheetState();
}

class _InvoiceSheetState extends State<_InvoiceSheet> {
  Invoice? _invoice;
  String? _error;
  bool _cargando = true;

  /// El cuadro de datos crudos arranca cerrado: son más de 40 líneas y solo
  /// hacen falta cuando hay que comparar la minifactura contra lo que hay en la
  /// base. El desglose de arriba es lo que se lee; este es lo que se audita.
  bool _datosAbiertos = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final inv = await api.getInvoiceById(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _invoice = inv;
        _cargando = false;
        _error = inv == null ? 'No se encontró la minifactura.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la minifactura: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const _Handle(),
              _barra(context),
              const Divider(height: 1),
              Expanded(child: _cuerpo(scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _barra(BuildContext context) {
    final inv = _invoice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: MuevexTheme.primaryColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.receipt_long,
                size: 20, color: MuevexTheme.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inv == null ? 'Minifactura' : inv.numeroFactura,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                if (inv != null) _chipEstado(inv.status),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            color: const Color(0xFF6B7280),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo(ScrollController controller) {
    if (_cargando) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final inv = _invoice;
    if (inv == null) {
      return _aviso(
        controller,
        _error ?? 'No se encontró la minifactura.',
        reintentar: true,
      );
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (_error != null) ...[
          _avisoInline(_error!),
          const SizedBox(height: 16),
        ],
        _bloqueEmisor(inv),
        const SizedBox(height: 16),
        _bloqueServicio(inv),
        const SizedBox(height: 16),
        _bloqueRenglones(inv),
        const SizedBox(height: 16),
        _bloqueTotales(inv),
        const SizedBox(height: 16),
        _bloqueDatos(inv),
        const SizedBox(height: 16),
        _pie(),
      ],
    );
  }

  Widget _chipEstado(InvoiceStatus status) {
    late final Color color;
    late final String texto;
    switch (status) {
      case InvoiceStatus.emitida:
        color = MuevexTheme.successColor;
        texto = 'Emitida';
        break;
      case InvoiceStatus.borrador:
        color = MuevexTheme.warningColor;
        texto = 'Borrador';
        break;
      case InvoiceStatus.anulada:
        color = const Color(0xFFDC2626);
        texto = 'Anulada';
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          if (status == InvoiceStatus.anulada && invVoidReason != null) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                invVoidReason!,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Motivo de anulación. Vive aquí para que el chip no tenga que recibirlo.
  String? get invVoidReason => _invoice?.voidedReason;

  /// Aviso de pie.
  ///
  /// La minifactura no es una factura electrónica de la DIAN: no lleva XML, ni
  /// CUFE, ni firma digital. Decirlo dentro del documento es lo honesto, porque
  /// quien lo guarda necesita saber qué es y qué no es. Si algún día se
  /// integra un proveedor de facturación electrónica, este texto es lo primero
  /// que hay que cambiar.
  Widget _pie() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Minifactura de MUEVEX. No es una factura electrónica de la DIAN: '
              'no tiene firma digital ni CUFE. Sirve como comprobante del '
              'servicio prestado.',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueEmisor(Invoice inv) {
    return _tarjeta([
      const _Rotulo('Emisor'),
      Text(inv.emisorNombre,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827))),
      const SizedBox(height: 2),
      Text('NIT ${inv.emisorNit}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
      Text('${inv.emisorDireccion}, ${inv.emisorCiudad}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
      if (inv.emisorResolucionDian != null &&
          inv.emisorResolucionDian!.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('Resolución DIAN ${inv.emisorResolucionDian}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
      ],
      const Divider(height: 24),
      const _Rotulo('Receptor'),
      Text(inv.receptorNombre,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827))),
      if (inv.receptorEmail != null && inv.receptorEmail!.isNotEmpty)
        Text(inv.receptorEmail!,
            style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
      const SizedBox(height: 8),
      _dato('Emitida', _fecha(inv.fechaEmision)),
      if (inv.fechaVencimiento != null)
        _dato('Vence', _fecha(inv.fechaVencimiento!)),
    ]);
  }

  Widget _bloqueServicio(Invoice inv) {
    return _tarjeta([
      const _Rotulo('Servicio'),
      Text(inv.servicioDescripcion,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827))),
      if (inv.servicioOrigen != null && inv.servicioOrigen!.isNotEmpty) ...[
        const SizedBox(height: 6),
        _fila(Icons.trip_origin, inv.servicioOrigen!),
      ],
      if (inv.servicioDestino != null && inv.servicioDestino!.isNotEmpty)
        _fila(Icons.place_outlined, inv.servicioDestino!),
      if (inv.servicioFecha != null)
        _dato('Fecha del servicio', _fecha(inv.servicioFecha!)),
      if (inv.servicioDistanciaKm != null)
        _dato('Distancia', '${inv.servicioDistanciaKm!.toStringAsFixed(1)} km'),
    ]);
  }

  Widget _bloqueRenglones(Invoice inv) {
    if (inv.items.isEmpty) {
      return const SizedBox.shrink();
    }
    return _tarjeta([
      const _Rotulo('Detalle'),
      for (final it in inv.items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.descripcion,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827))),
                    if (it.codigo != null)
                      Text(it.codigo!,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(money(it.total),
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827))),
            ],
          ),
        ),
    ]);
  }

  Widget _bloqueTotales(Invoice inv) {
    return _tarjeta([
      _totalFila('Subtotal', money(inv.subtotal)),
      const SizedBox(height: 6),
      _totalFila(
        'IVA (${inv.ivaPorcentaje.toStringAsFixed(0)}%)',
        money(inv.ivaValor),
      ),
      if (inv.retencionFuenteValor > 0) ...[
        const SizedBox(height: 6),
        _totalFila(
            'Retención en la fuente', '-${money(inv.retencionFuenteValor)}'),
      ],
      if (inv.retencionIcaValor > 0) ...[
        const SizedBox(height: 6),
        _totalFila('Retención ICA', '-${money(inv.retencionIcaValor)}'),
      ],
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1),
      ),
      Row(
        children: [
          const Text(
            'Total',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827)),
          ),
          const Spacer(),
          Text(
            money(inv.total),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: MuevexTheme.secondaryColor,
            ),
          ),
        ],
      ),
    ]);
  }

  /// Cuadro con los campos de la minifactura tal como los guarda la base.
  ///
  /// Los nombres van en snake_case a propósito: son los mismos que salen en
  /// el `SELECT` y en la consola de Supabase, para poder comparar sin tener
  /// que traducción de por medio en medio de una conciliación.
  Widget _bloqueDatos(Invoice inv) {
    return _tarjeta([
      InkWell(
        onTap: () => setState(() => _datosAbiertos = !_datosAbiertos),
        child: Row(
          children: [
            const Expanded(child: _Rotulo('Datos de la minifactura')),
            Text(
              _datosAbiertos ? 'Ocultar' : 'Ver todo',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MuevexTheme.primaryColor,
              ),
            ),
            Icon(
              _datosAbiertos ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: MuevexTheme.primaryColor,
            ),
          ],
        ),
      ),
      if (_datosAbiertos) ...[
        const Divider(height: 18),
        for (final c in _camposTecnicos(inv)) _campo(c),
      ],
    ]);
  }

  List<_Campo> _camposTecnicos(Invoice inv) {
    final out = <_Campo>[];
    void n(String nombre, Object? valor) =>
        out.add(_Campo(nombre, _bruto(valor)));

    // Identificación
    n('id', inv.id);
    n('numero_factura', inv.numeroFactura);
    n('service_id', inv.serviceId);
    n('customer_id', inv.customerId);
    n('driver_id', inv.driverId);

    // Fechas
    n('fecha_emision', inv.fechaEmision);
    n('fecha_vencimiento', inv.fechaVencimiento);

    // Emisor
    n('emisor_nit', inv.emisorNit);
    n('emisor_nombre', inv.emisorNombre);
    n('emisor_direccion', inv.emisorDireccion);
    n('emisor_ciudad', inv.emisorCiudad);
    n('emisor_telefono', inv.emisorTelefono);
    n('emisor_email', inv.emisorEmail);
    n('emisor_resolucion_dian', inv.emisorResolucionDian);
    n('emisor_fecha_resolucion', inv.emisorFechaResolucion);
    n('emisor_prefijo', inv.emisorPrefijo);
    n('emisor_rango_inicial', inv.emisorRangoInicial);
    n('emisor_rango_final', inv.emisorRangoFinal);

    // Receptor
    n('receptor_nit', inv.receptorNit);
    n('receptor_nombre', inv.receptorNombre);
    n('receptor_direccion', inv.receptorDireccion);
    n('receptor_ciudad', inv.receptorCiudad);
    n('receptor_telefono', inv.receptorTelefono);
    n('receptor_email', inv.receptorEmail);

    // Snapshot del servicio
    n('servicio_descripcion', inv.servicioDescripcion);
    n('servicio_origen', inv.servicioOrigen);
    n('servicio_destino', inv.servicioDestino);
    n('servicio_distancia_km', inv.servicioDistanciaKm);
    n('servicio_fecha', inv.servicioFecha);

    // Montos
    n('subtotal', inv.subtotal);
    n('iva_porcentaje', inv.ivaPorcentaje);
    n('iva_valor', inv.ivaValor);
    n('retencion_fuente_porcentaje', inv.retencionFuentePorcentaje);
    n('retencion_fuente_valor', inv.retencionFuenteValor);
    n('retencion_ica_porcentaje', inv.retencionIcaPorcentaje);
    n('retencion_ica_valor', inv.retencionIcaValor);
    n('total', inv.total);

    // Estado y control
    n('status', inv.status.dbName);
    n('pdf_url', inv.pdfUrl);
    n('notas', inv.notas);

    // Auditoría
    n('created_at', inv.createdAt);
    n('updated_at', inv.updatedAt);
    n('emitted_at', inv.emittedAt);
    n('voided_at', inv.voidedAt);
    n('voided_reason', inv.voidedReason);
    n(
        'items',
        inv.items.isEmpty
            ? 0
            : '${inv.items.length} renglón${inv.items.length == 1 ? '' : 'es'}');

    return out;
  }

  /// Convierte un valor de la minifactura a texto sin inventar formato.
  ///
  /// Las fechas van en ISO 8601, que es como las manda la base, y no en
  /// `28/09/2026`: este cuadro sirve para comparar, y `28/09/2026` no es lo
  /// que hay guardado. Los nulos se marcan con «—» para que se distingan de
  /// una cadena vacía.
  String _bruto(Object? v) {
    if (v == null) return '—';
    if (v is DateTime) return v.toIso8601String();
    if (v is double) return v.toStringAsFixed(2);
    final s = v.toString();
    return s.isEmpty ? '—' : s;
  }

  Widget _campo(_Campo c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 165,
            child: Text(
              c.nombre,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF9CA3AF)),
            ),
          ),
          Expanded(
            child: Text(
              c.valor,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── piezas pequeñas ────────────────────────────────────────────────────

  Widget _aviso(ScrollController controller, String texto,
      {bool reintentar = false}) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _avisoInline(texto),
        if (reintentar) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ],
    );
  }

  Widget _avisoInline(String texto) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MuevexTheme.warningColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: MuevexTheme.warningColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                  fontSize: 12.5,
                  color: MuevexTheme.warningColor,
                  height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _fila(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(texto,
                style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
          ),
        ],
      ),
    );
  }

  Widget _dato(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(valor,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827))),
          ),
        ],
      ),
    );
  }

  Widget _totalFila(String label, String valor) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF374151))),
        const Spacer(),
        Text(valor,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827))),
      ],
    );
  }

  String _fecha(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$day/$m/${d.year}';
  }
}

/// Una fila del cuadro de datos: el nombre de la columna y su valor.
class _Campo {
  const _Campo(this.nombre, this.valor);

  final String nombre;
  final String valor;
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFD1D5DB),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }
}
