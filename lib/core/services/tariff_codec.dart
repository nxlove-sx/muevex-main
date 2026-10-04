/// Bridge entre el motor de tarifas ([TarifaEngine]), el estado del formulario
/// y las columnas de Supabase.
///
/// Dart puro a propósito: lo usan el formulario del cliente (para cotizar) y el
/// conductor (para mostrar por qué se cobró eso), y así ambos leen exactamente
/// los mismos datos.
///
/// Decisión de diseño: el `load_type` del servicio deja de elegirlo el cliente
/// y se deduce de los artículos ([tipoCargaLegacy]). Así la columna sigue
/// viva para los filtros que ya la usaban, sin obligar a elegir entre
/// "artículos" y "tipo de carga".
library;

import 'tariff_engine.dart';

/// Convierte el estado del formulario en una entrada del motor.
///
/// Si el cliente ya eligió artículos, mandan ellos. Si no, se deduce del
/// `loadType` antiguo para que el precio no salga a cero mientras se migra la
/// interfaz.
TarifaEntrada entradaDesdeFormulario(
  Map<String, dynamic> form,
  double distanciaKm,
) {
  final articulos = articulosDesdeJson(form['items']);
  return TarifaEntrada(
    distanciaKm: distanciaKm,
    articulos: articulos.isNotEmpty
        ? articulos
        : articulosPorTipoCarga(form['loadType'] as String?),
    pisosRecogida: _int(form['floorsPickup'], _int(form['floors'], 0)),
    pisosEntrega: _int(form['floorsDelivery'], _int(form['floors'], 0)),
    ayudante: ayudanteDesdeDb(form['helperOrigin'] as String?),
    viajes: _int(form['trips'], 1),
  );
}

/// Artículos representativos por cada `load_type` del formulario antiguo.
///
/// Solo se usa cuando el cliente todavía no ha elegido artículos. No pretende
/// ser preciso: es el puente para que el precio no se vaya a $0 mientras se
/// despliega el selector de artículos.
List<ArticuloSeleccionado> articulosPorTipoCarga(String? loadType) {
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

/// Lee `[{"id":"lavadora","cantidad":2}]` desde la base de datos o el
/// formulario. Tolera `null`, listas vacías y ids que ya no existen en el
/// catálogo (un artículo retirado no debe romper la lectura del historial).
List<ArticuloSeleccionado> articulosDesdeJson(dynamic json) {
  if (json is! List) return const [];
  final salida = <ArticuloSeleccionado>[];
  for (final crudo in json) {
    if (crudo is! Map) continue;
    final id = (crudo['id'] ?? crudo['articuloId']) as String?;
    if (id == null || id.isEmpty) continue;
    final cantidad = (crudo['cantidad'] as num?)?.toInt() ?? 1;
    if (cantidad <= 0) continue;
    final articulo = TarifaEngine.articuloPorId(id);
    if (articulo == null) continue; // artículo retirado: se ignora en silencio
    salida.add(ArticuloSeleccionado(articulo, cantidad));
  }
  return salida;
}

/// Serializa la selección para guardarla en `services.items`.
///
/// La forma es una lista de mapas y no de ids sueltos, porque el
/// comprobante tiene que poder explicar el precio aunque el catálogo cambie.
List<Map<String, dynamic>> articulosAMaps(
    List<ArticuloSeleccionado> articulos) {
  return articulos
      .map(
          (a) => <String, dynamic>{'id': a.articulo.id, 'cantidad': a.cantidad})
      .toList();
}

/// Deduce el `load_type` legacy a partir de los artículos.
///
/// Se mantiene la columna porque el conductor y varios filtros del historial la
/// leen, pero el cliente ya no la elige: sale de lo que réellement cargó.
String tipoCargaLegacy(List<ArticuloSeleccionado> articulos) {
  if (articulos.isEmpty) return 'cajas';
  final categorias = articulos.map((a) => a.articulo.categoria).toSet();
  if (categorias.contains(CategoriaArticulo.muebleria)) return 'muebles';
  if (categorias.contains(CategoriaArticulo.electrodomestico)) {
    return 'electrodomesticos';
  }
  if (categorias.contains(CategoriaArticulo.electronica) ||
      categorias.contains(CategoriaArticulo.climatizacion)) {
    return 'electrodomesticos';
  }
  return 'cajas';
}

/// Traduce el valor de `services.helper_origin` al enum del motor.
OrigenAyudante ayudanteDesdeDb(String? valor) {
  switch (valor) {
    case 'cliente':
      return OrigenAyudante.cliente;
    case 'plataforma':
      return OrigenAyudante.plataforma;
    default:
      return OrigenAyudante.incluido;
  }
}

/// Serializa el enum para guardarlo.
String ayudanteAMaps(OrigenAyudante origen) => origen.name;

/// Convierte el desglose a la forma que se guarda en
/// `services.tariff_breakdown`.
///
/// Se guarda el resultado ya calculado, no los datos de entrada: si un día
/// cambia la tabla de precios, el comprobante de un servicio viejo debe
/// seguir enseñando lo que se cobró, no lo que cobraría hoy.
Map<String, dynamic> desgloseAMap(Tarifa tarifa) => {
      'total': tarifa.total,
      'lineas': tarifa.lineas
          .map((l) => {
                'concepto': l.concepto,
                'monto': l.monto,
                'detalle': l.detalle,
              })
          .toList(),
      'tipo_carga': tarifa.tipoCarga.name,
      'es_mudanza': tarifa.esMudanza,
      'viajes': tarifa.viajes,
      'peso_kg': tarifa.pesoKg,
      'volumen_m3': tarifa.volumenM3,
      'capacidad_minima_kg': tarifa.capacidadMinimaKg,
      'vehiculo': tarifa.categoriaSugerida.nombre,
    };

/// Reconstruye un desglose guardado. Devuelve `null` si no hay nada guardado
/// (servicios cotizados con la fórmula antigua).
Tarifa? desgloseDesdeMap(dynamic json) {
  if (json is! Map) return null;
  final lineasRaw = json['lineas'];
  if (lineasRaw is! List) return null;
  final lineas = lineasRaw
      .whereType<Map>()
      .map((m) => LineaTarifa(
            (m['concepto'] ?? '').toString(),
            (m['monto'] as num?)?.toDouble() ?? 0,
            detalle: m['detalle']?.toString(),
          ))
      .toList();
  return Tarifa(
    total: (json['total'] as num?)?.toDouble() ?? 0,
    lineas: lineas,
    tipoCarga: json['tipo_carga'] == 'delicada'
        ? TipoCarga.delicada
        : TipoCarga.rustica,
    pesoKg: (json['peso_kg'] as num?)?.toDouble() ?? 0,
    volumenM3: (json['volumen_m3'] as num?)?.toDouble() ?? 0,
    capacidadMinimaKg: (json['capacidad_minima_kg'] as num?)?.toInt() ?? 0,
    categoriaSugerida: TarifaEngine.categoriasVehiculo.first,
    esMudanza: json['es_mudanza'] == true,
    viajes: (json['viajes'] as num?)?.toInt() ?? 1,
  );
}

/// Etiqueta legible del tipo de carga, para el comprobante.
String etiquetaTipoCarga(String? dbName) {
  switch (dbName) {
    case 'delicada':
      return 'Carga delicada / mudanza';
    case 'rustica':
      return 'Carga rústica';
    default:
      return 'Carga';
  }
}

int _int(dynamic valor, int porDefecto) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  if (valor is String) return int.tryParse(valor) ?? porDefecto;
  return porDefecto;
}
