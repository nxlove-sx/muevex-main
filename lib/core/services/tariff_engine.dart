/// Motor de cálculo de tarifas de MUEVEX.
///
/// Sustituye a `PriceCalculator`, que usaba una fórmula lineal
/// (`$5.000 base + $2.000/km` desde el primer kilómetro) y por tanto cobraba
/// $9.000 por una carrera de 2 km. La tabla vigente fija un **mínimo de
/// $25.000 hasta 6 km** y escala por **bandas de distancia**, no por km.
///
/// Las reglas implementadas aquí provienen de la propuesta de tarifas de la
/// plataforma de referencia (TRANSPERSQUI). Sección del documento → regla:
///
///   1. Servicio básico  → [_bandaDistancia]          (bandas 0-6 … >25 km)
///   2. Carga delicada   → [sueloDelicada]            (mín. $40.000 / $50.000)
///   3. Recargos         → [ArticuloCatalogo]         (tabla por artículo)
///   4. Pisos            → [TarifaEngine.pisoFee]     ($10.000/piso/viaje)
///   5. Ayudante         → [TarifaEngine.ayudanteFee] ($30.000 si lo pone la plataforma)
///   6. Varios viajes    → [_factorViajes]            (100 % / 85 % / 80 %)
///   7. Vehículo         → [categoriaParaPeso]        (por capacidad autorizada)
///   8. Experiencia      → el cliente elige artículos, nunca el peso
///
/// Reglas de diseño que conviene no romper:
///
/// * **Dart puro.** Sin `package:flutter`, sin Supabase, sin `latlong2`.
///   Así el motor se copia sin cambios a las dos apps y se puede probar con
///   `flutter test` sin montar widget tests.
/// * **Determinista.** Misma entrada ⇒ mismo total, en el dispositivo y en el
///   panel de Supabase. Nunca depende de `DateTime.now()` ni de aleatoriedad.
/// * **Sin euros negativos.** Cualquier entrada rara (distancia 0, lista de
///   artículos vacía, pisos negativos) cae a un valor seguro en vez de
///   producir un total negativo o `NaN`, que contaminaría `price_base`.
library;

import 'dart:math' as math;

/// Clasificación de la carga. Decide la tarifa mínima aplicable.
enum TipoCarga {
  /// Bultos y mercancía no delicada: arroz, plátano, yuca, cemento,
  /// herramientas, materiales de construcción, cajas. Tarifa mínima $25.000.
  rustica('Carga rústica'),

  /// Muebles, electrodomésticos, loza, espejos. Tarifa mínima $40.000.
  delicada('Carga delicada / mudanza');

  const TipoCarga(this.label);

  final String label;
}

/// Quién pone la persona que ayuda a cargar y descargar.
enum OrigenAyudante {
  /// El servicio básico ya incluye al conductor: no se cobra nada extra.
  incluido('Incluido en el servicio'),

  /// El cliente trae un acompañante: $0.
  cliente('Lo aporta el cliente'),

  /// La plataforma hiringa un ayudante: [TarifaEngine.ayudanteFee].
  plataforma('Ayudante de TRANSPERSQUI');

  const OrigenAyudante(this.label);

  final String label;

  /// Si este origen implica un cobro adicional.
  bool get tieneCosto => this == OrigenAyudante.plataforma;
}

/// Un artículo del catálogo.
///
/// El cliente **nunca** escribe el peso: elige artículos de [_catalogo] y el
/// motor conoce el peso, volumen, fragilidad y dificultad de cada uno. Ese es
/// el punto 8 del documento.
///
/// [recargo] es el surcharge que suma el artículo cuando va **por separado**
/// (un solo electrodoméstico, una colchoneta suelta). En una mudanza con varios
/// artículos no se suman uno a uno: la tarifa se calcula conjunta para no
/// inflar el total, tal como pide la sección 3 del documento.
class ArticuloCatalogo {
  const ArticuloCatalogo({
    required this.id,
    required this.nombre,
    required this.recargo,
    required this.pesoKg,
    required this.volumenM3,
    this.fragil = false,
    this.categoria = CategoriaArticulo.otro,
  });

  /// Clave estable. Se persiste en `services.load_details['articulos']`.
  final String id;

  /// Etiqueta que ve el cliente.
  final String nombre;

  /// Recargo en pesos cuando el artículo va por separado.
  final double recargo;

  /// Peso estimado. **Calibrar con datos reales**: son valores de referencia
  /// tomados del sentido común, no del documento de origen (que no los da), y
  /// de ellos depende la asignación de vehículo.
  final double pesoKg;

  /// Volumen estimado en metros cúbicos.
  final double volumenM3;

  /// Si requiere cuidado especial (loza, cristalería, TVs, espejos).
  final bool fragil;

  final CategoriaArticulo categoria;

  /// Copia inmutable con otro id, para artículos que el usuario no encuentra en
  /// el catálogo ("otro").
  ArticuloCatalogo copyWith({String? id, String? nombre}) => ArticuloCatalogo(
        id: id ?? this.id,
        nombre: nombre ?? this.nombre,
        recargo: recargo,
        pesoKg: pesoKg,
        volumenM3: volumenM3,
        fragil: fragil,
        categoria: categoria,
      );
}

/// Agrupación de artículos, usada para elegir la tarifa mínima y la etiqueta.
enum CategoriaArticulo {
  muebleria,
  electrodomestico,
  electronica,
  climatizacion,
  construccion,
  bulto,
  caja,
  fragil,
  otro,
}

/// Un artículo seleccionado por el cliente, con su cantidad.
class ArticuloSeleccionado {
  const ArticuloSeleccionado(this.articulo, [this.cantidad = 1])
      : assert(cantidad >= 0, 'la cantidad no puede ser negativa');

  final ArticuloCatalogo articulo;
  final int cantidad;

  double get pesoKg => articulo.pesoKg * cantidad;
  double get volumenM3 => articulo.volumenM3 * cantidad;
  double get recargoTotal => articulo.recargo * cantidad;
  bool get fragil => articulo.fragil;
}

/// Una categoría de motocarro y su franja de capacidad autorizada.
///
/// La capacidad es **por vehículo**, no derivada del cilindraje. Dos motocarros
/// del mismo cilindraje pueden tener capacidades distintas, así que la regla de
/// asignación compara siempre contra `vehicles.capacity` (el máximo autorizado
/// registrado por el conductor), nunca contra los cc.
class CategoriaVehiculo {
  const CategoriaVehiculo({
    required this.nombre,
    required this.cc,
    required this.capacidadMinKg,
    required this.capacidadMaxKg,
  });

  final String nombre;
  final int cc;
  final int capacidadMinKg;
  final int capacidadMaxKg;

  /// Rango real tras aplicar el margen de seguridad.
  int get capacidadUtilMinKg =>
      (capacidadMinKg * TarifaEngine.margenSeguridad).round();
  int get capacidadUtilMaxKg =>
      (capacidadMaxKg * TarifaEngine.margenSeguridad).round();

  bool cubre(double pesoKg) => pesoKg <= capacidadUtilMaxKg;

  @override
  String toString() => '$nombre ${cc}cc (${capacidadMinKg}–$capacidadMaxKg kg)';
}

/// Una línea del desglose que ve el cliente antes de confirmar.
class LineaTarifa {
  const LineaTarifa(this.concepto, this.monto, {this.detalle});

  final String concepto;
  final double monto;
  final String? detalle;
}

/// Resultado completo del cálculo.
class Tarifa {
  const Tarifa({
    required this.total,
    required this.lineas,
    required this.tipoCarga,
    required this.pesoKg,
    required this.volumenM3,
    required this.capacidadMinimaKg,
    required this.categoriaSugerida,
    required this.esMudanza,
    required this.viajes,
  });

  /// Total a cobrar, ya redondeado.
  final double total;

  /// Desglose listo para pintar en el comprobante.
  final List<LineaTarifa> lineas;

  final TipoCarga tipoCarga;

  /// Peso total estimado de la carga.
  final double pesoKg;
  final double volumenM3;

  /// Capacidad autorizada mínima que debe tener el vehículo asignado.
  final int capacidadMinimaKg;
  final CategoriaVehiculo categoriaSugerida;

  /// `true` cuando la tarifa se calculó conjunta (varios artículos
  /// delicados). En ese caso los recargos unitarios van dentro de la base.
  final bool esMudanza;

  final int viajes;
}

/// Entrada del cálculo. Todo lo que la app sabe del servicio antes de
/// confirmar.
class TarifaEntrada {
  const TarifaEntrada({
    required this.distanciaKm,
    this.articulos = const <ArticuloSeleccionado>[],
    this.pisosRecogida = 0,
    this.pisosEntrega = 0,
    this.ayudante = OrigenAyudante.incluido,
    this.viajes = 1,
  });

  final double distanciaKm;
  final List<ArticuloSeleccionado> articulos;
  final int pisosRecogida;
  final int pisosEntrega;
  final OrigenAyudante ayudante;
  final int viajes;

  TarifaEntrada copyWith({
    double? distanciaKm,
    List<ArticuloSeleccionado>? articulos,
    int? pisosRecogida,
    int? pisosEntrega,
    OrigenAyudante? ayudante,
    int? viajes,
  }) =>
      TarifaEntrada(
        distanciaKm: distanciaKm ?? this.distanciaKm,
        articulos: articulos ?? this.articulos,
        pisosRecogida: pisosRecogida ?? this.pisosRecogida,
        pisosEntrega: pisosEntrega ?? this.pisosEntrega,
        ayudante: ayudante ?? this.ayudante,
        viajes: viajes ?? this.viajes,
      );
}

/// Motor de tarifas.
///
/// Ver [TarifaEntrada] para la forma de la entrada y [Tarifa] para la salida.
class TarifaEngine {
  const TarifaEngine._();

  // ── Constantes de la propuesta ──────────────────────────────────────────

  /// Carrera mínima: $25.000 hasta 6 km.
  static const double tarifaMinimaRustica = 25000;

  /// Suelo para carga delicada: $40.000, o $50.000 cuando son varios artículos.
  static const double sueloDelicada = 40000;
  static const double sueloMudanza = 50000;

  /// A partir de este número de artículos delicados la tarifa se calcula
  /// conjunta (punto 3: "no sumarán individualmente en una mudanza completa").
  static const int umbralMudanza = 2;

  /// Pisos y escaleras: $10.000 por piso **y por viaje**, calculado por separado
  /// en recogida y en entrega (punto 4).
  static const double pisoFee = 10000;

  /// Ayudante que pone la plataforma: $30.000 (punto 5).
  static const double ayudanteFee = 30000;

  /// Descuento del 2º viaje (punto 6).
  static const double factorSegundoViaje = 0.85;

  /// Descuento del 3º viaje en adelante (punto 6).
  static const double factorTercerViaje = 0.80;

  /// Por km por encima de 25 km (punto 1).
  static const double kmAdicional = 2000;

  /// Distancia a partir de la cual se cobra el km adicional.
  static const double kmGratisAdicional = 25;

  /// Se cobra solo el 90 % de la capacidad autorizada, para no llegar al tope
  /// legal. La asignación real usa [CategoriaVehiculo.capacidadUtilMaxKg].
  static const double margenSeguridad = 0.9;

  /// Bandas de distancia para carga rústica: techo del tramo → precio.
  /// El último es el precio base para >25 km, del que se descuenta el km gratis.
  static const List<MapEntry<double, double>> bandasDistancia = [
    MapEntry(6, 25000),
    MapEntry(10, 30000),
    MapEntry(15, 35000),
    MapEntry(20, 40000),
    MapEntry(25, 45000),
  ];

  // ── Catálogo ────────────────────────────────────────────────────────────

  /// Artículos seleccionables con su peso, volumen y recargo.
  ///
  /// Los pesos y volúmenes son **estimaciones de referencia**: el documento de
  /// origen no los da. Hay que calibrarlos con los servicios reales antes de
  /// cobrar en serio, porque de ellos depende la asignación de vehículo. Un
  /// poids subestimado manda un motocarro demasiado pequeño y la mudanza se
  /// rechaza en la calle.
  static const List<ArticuloCatalogo> catalogo = [
    // — Mudanza: muebles —
    ArticuloCatalogo(
      id: 'colchon_sencillo',
      nombre: 'Colchón sencillo',
      recargo: 5000,
      pesoKg: 35,
      volumenM3: 0.7,
      categoria: CategoriaArticulo.muebleria,
    ),
    ArticuloCatalogo(
      id: 'colchon_doble',
      nombre: 'Colchón doble / queen',
      recargo: 10000,
      pesoKg: 60,
      volumenM3: 1.2,
      categoria: CategoriaArticulo.muebleria,
    ),
    ArticuloCatalogo(
      id: 'cama_desarmada',
      nombre: 'Cama desarmada',
      recargo: 10000,
      pesoKg: 70,
      volumenM3: 1.5,
      categoria: CategoriaArticulo.muebleria,
    ),
    ArticuloCatalogo(
      id: 'sofa_2',
      nombre: 'Sofá 2 puestos',
      recargo: 10000,
      pesoKg: 50,
      volumenM3: 1.1,
      categoria: CategoriaArticulo.muebleria,
    ),
    ArticuloCatalogo(
      id: 'sofa_3',
      nombre: 'Sofá 3 puestos',
      recargo: 15000,
      pesoKg: 75,
      volumenM3: 1.8,
      categoria: CategoriaArticulo.muebleria,
    ),
    ArticuloCatalogo(
      id: 'comedor',
      nombre: 'Comedor (mesa + sillas)',
      recargo: 15000,
      pesoKg: 80,
      volumenM3: 1.6,
      categoria: CategoriaArticulo.muebleria,
    ),
    ArticuloCatalogo(
      id: 'closet_desarmado',
      nombre: 'Clóset desarmado',
      recargo: 10000,
      pesoKg: 100,
      volumenM3: 1.4,
      categoria: CategoriaArticulo.muebleria,
    ),
    ArticuloCatalogo(
      id: 'closet_armado',
      nombre: 'Clóset armado',
      recargo: 20000,
      pesoKg: 160,
      volumenM3: 2.1,
      categoria: CategoriaArticulo.muebleria,
    ),

    // — Mudanza: electrodomésticos —
    ArticuloCatalogo(
      id: 'lavadora',
      nombre: 'Lavadora',
      recargo: 10000,
      pesoKg: 75,
      volumenM3: 0.8,
      categoria: CategoriaArticulo.electrodomestico,
    ),
    ArticuloCatalogo(
      id: 'nevera_pequena',
      nombre: 'Nevera pequeña',
      recargo: 15000,
      pesoKg: 45,
      volumenM3: 0.5,
      categoria: CategoriaArticulo.electrodomestico,
    ),
    ArticuloCatalogo(
      id: 'nevera_mediana',
      nombre: 'Nevera mediana / grande',
      recargo: 20000,
      pesoKg: 80,
      volumenM3: 0.9,
      categoria: CategoriaArticulo.electrodomestico,
    ),

    // — Mudanza: electrónica y climatización —
    ArticuloCatalogo(
      id: 'tv_43',
      nombre: 'TV hasta 43"',
      recargo: 10000,
      pesoKg: 12,
      volumenM3: 0.15,
      fragil: true,
      categoria: CategoriaArticulo.electronica,
    ),
    ArticuloCatalogo(
      id: 'tv_55',
      nombre: 'TV de 44" a 55"',
      recargo: 15000,
      pesoKg: 18,
      volumenM3: 0.25,
      fragil: true,
      categoria: CategoriaArticulo.electronica,
    ),
    ArticuloCatalogo(
      id: 'tv_70',
      nombre: 'TV de 56" a 70"',
      recargo: 20000,
      pesoKg: 28,
      volumenM3: 0.4,
      fragil: true,
      categoria: CategoriaArticulo.electronica,
    ),
    ArticuloCatalogo(
      id: 'aire_acondicionado',
      nombre: 'Aire acondicionado',
      recargo: 10000,
      pesoKg: 35,
      volumenM3: 0.4,
      categoria: CategoriaArticulo.climatizacion,
    ),

    // — Frágil —
    ArticuloCatalogo(
      id: 'espejo_vitrina',
      nombre: 'Espejo / vitrina grande',
      recargo: 20000,
      pesoKg: 45,
      volumenM3: 0.6,
      fragil: true,
      categoria: CategoriaArticulo.fragil,
    ),
    ArticuloCatalogo(
      id: 'loza_cristaleria',
      nombre: 'Loza / cristalería (caja)',
      recargo: 5000,
      pesoKg: 15,
      volumenM3: 0.2,
      fragil: true,
      categoria: CategoriaArticulo.fragil,
    ),

    // — Construcción —
    ArticuloCatalogo(
      id: 'trompo',
      nombre: 'Trompo de construcción',
      recargo: 15000,
      pesoKg: 110,
      volumenM3: 0.9,
      categoria: CategoriaArticulo.construccion,
    ),
    ArticuloCatalogo(
      id: 'rana',
      nombre: 'Rana / compactadora',
      recargo: 15000,
      pesoKg: 95,
      volumenM3: 0.7,
      categoria: CategoriaArticulo.construccion,
    ),

    // — Rústica (no paga el mínimo de mudanza) —
    ArticuloCatalogo(
      id: 'caja',
      nombre: 'Caja / bulto',
      recargo: 0,
      pesoKg: 20,
      volumenM3: 0.12,
      categoria: CategoriaArticulo.caja,
    ),
    ArticuloCatalogo(
      id: 'bulto_agricola',
      nombre: 'Bulto agrícola (arroz, yuca…)',
      recargo: 0,
      pesoKg: 50,
      volumenM3: 0.06,
      categoria: CategoriaArticulo.bulto,
    ),
    ArticuloCatalogo(
      id: 'herramientas',
      nombre: 'Herramientas / material',
      recargo: 0,
      pesoKg: 30,
      volumenM3: 0.1,
      categoria: CategoriaArticulo.construccion,
    ),
  ];

  /// Categorías de motocarro, del más pequeño al más grande.
  ///
  /// El `cc` es **informativo**: sirve para etiquetar y para agrupar, no para
  /// decidir capacidad. La capacidad real sale de `vehicles.capacity`.
  static const List<CategoriaVehiculo> categoriasVehiculo = [
    CategoriaVehiculo(
      nombre: 'Motocarro 200',
      cc: 200,
      capacidadMinKg: 410,
      capacidadMaxKg: 510,
    ),
    CategoriaVehiculo(
      nombre: 'Motocarro 250',
      cc: 250,
      capacidadMinKg: 650,
      capacidadMaxKg: 750,
    ),
    CategoriaVehiculo(
      nombre: 'Motocarro 300',
      cc: 300,
      capacidadMinKg: 800,
      capacidadMaxKg: 1000,
    ),
    CategoriaVehiculo(
      nombre: 'Motocarro 500',
      cc: 500,
      capacidadMinKg: 1000,
      capacidadMaxKg: 1500,
    ),
  ];

  /// Busca un artículo por id. Devuelve `null` si no existe.
  static ArticuloCatalogo? articuloPorId(String id) {
    for (final a in catalogo) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Artículo genérico para lo que el cliente escriba y no esté en el
  /// catálogo. Hereda la carga más pesada conocida para no subestimar.
  static ArticuloCatalogo articuloLibre(String nombre) => ArticuloCatalogo(
        id: 'otro',
        nombre: nombre.trim().isEmpty ? 'Otro' : nombre.trim(),
        recargo: 5000,
        pesoKg: 25,
        volumenM3: 0.1,
        categoria: CategoriaArticulo.otro,
      );

  // ── Cálculo ─────────────────────────────────────────────────────────────

  /// Calcula la tarifa completa.
  static Tarifa calcular(TarifaEntrada e) {
    final viajes = math.max(1, e.viajes);
    final distancia = math.max(0.0, e.distanciaKm);
    final articulos = e.articulos.where((a) => a.cantidad > 0).toList();

    // Tipo de carga y peso. Basta un solo artículo delicado para que la
    // tarifa sea de mudanza, aunque el cliente solo lleve una nevera. Las cajas
    // no cuentan como delicadas: son los bultos los que suben el mínimo.
    final articulosDelicados = articulos
        .where((a) => a.articulo.categoria != CategoriaArticulo.caja)
        .length;
    final tipoCarga =
        articulosDelicados > 0 ? TipoCarga.delicada : TipoCarga.rustica;

    final pesoKg = articulos.fold<double>(0, (s, a) => s + a.pesoKg);
    final volumenM3 = articulos.fold<double>(0, (s, a) => s + a.volumenM3);

    final esMudanza = articulosDelicados >= umbralMudanza;

    // 1) Base por distancia.
    final banda = bandaDistancia(distancia);
    var base = banda;

    // 2) Suelo por tipo de carga. En mudanza conjunta la base ya absorbe los
    //    recargos unitarios: por eso NO se suman después.
    if (tipoCarga == TipoCarga.delicada) {
      final suelo = esMudanza ? sueloMudanza : sueloDelicada;
      if (base < suelo) base = suelo;
    }

    // 3) Recargos por artículo, solo si NO es mudanza conjunta.
    //
    // El documento dice "ADEMÁS de la tarifa base, la aplicación podrá aplicar
    // recargos" (punto 3), así que un artículo suelto paga su recargo encima
    // del suelo. Consecuencia a validar con el negocio: una lavadora sola
    // ($40.000 + $10.000) y una mudanza completa ($50.000) cuestan casi igual.
    // Si se prefiere que el suelo ya absorba el artículo, la alternativa es
    // tomar `sueloDelicada + sueloMudanza` en vez de sumar el recargo.
    final recargoArticulos = esMudanza ? 0.0 : _recargoArticulos(articulos);
    if (!esMudanza) base += recargoArticulos;

    // 5) Ayudante.
    final ayudante = e.ayudante.tieneCosto ? ayudanteFee : 0.0;

    // 6) Varios viajes: se aplica al costo del viaje (base + recargos +
    //    ayudante), no a los pisos, que ya se cobran "por viaje" en el
    //    punto 4 y no deben reducirse dos veces.
    //
    //    El redondeo a miles va AQUÍ y no sobre el total. El factor de varios
    //    viajes puede dar medios miles (1,85 × 50.000 = 92.500) y, si se
    //    redondeara el total, las líneas del desglose no sumarían lo que se
    //    cobra. Los pisos son siempre múltiplo de 1.000, así que redondear
    //    antes o después da EXACTAMENTE el mismo total: el precio no cambia,
    //    solo deja de descuadrarse el reparto.
    final subtotalViaje = base + ayudante;
    final factorViajes = _factorViajes(viajes);
    final costoViajes = _redondear(subtotalViaje * factorViajes);

    // 4) Pisos: recogida y entrega por separado, por cada viaje.
    final pisos = math.max(0, e.pisosRecogida) + math.max(0, e.pisosEntrega);
    final costoPisos = pisos * pisoFee * viajes;

    final total = _redondear(costoViajes + costoPisos);

    // 7) Vehículo sugerido.
    final categoria = categoriaParaPeso(pesoKg);

    // ── Desglose ──
    //
    // Invariante: **la suma de las líneas es siempre igual a [Tarifa.total]**.
    // El cliente suma lo que ve y compara con el total que le da la app; si
    // no cuadra, el desglose parece inventado. También lo necesita la factura:
    // sus renglones salen de estas líneas, y la función de Postgres solo añade
    // un renglón "AJUSTE" cuando la diferencia viene del precio que confirmó el
    // conductor. Con las líneas cuadrando, ese renglón aparece únicamente cuando
    // tiene sentido.
    final lineas = <LineaTarifa>[];

    // La línea de la base va SIN el recargo de artículos: el recargo tiene su
    // propia línea unas líneas más abajo. Antes se pintaba `base`, que ya lo
    // llevaba dentro, y el desglose mostraba el recargo dos veces.
    final baseSinRecargo = base - recargoArticulos;
    lineas.add(LineaTarifa(
      tipoCarga == TipoCarga.delicada
          ? 'Tarifa de mudanza / carga delicada'
          : 'Tarifa de servicio básico',
      baseSinRecargo,
      detalle: _detalleBanda(distancia),
    ));

    if (recargoArticulos > 0) {
      lineas.add(LineaTarifa(
        'Recargos por artículo',
        recargoArticulos,
        detalle: articulos
            .where((a) => a.articulo.recargo > 0)
            .map((a) => '${a.cantidad}× ${a.articulo.nombre}')
            .join(', '),
      ));
    }

    if (esMudanza) {
      lineas.add(LineaTarifa(
        'Tarifa conjunta',
        0,
        detalle: 'Incluye los recargos de los artículos para no '
            'proporcionar cobros desproporcionados.',
      ));
    }

    if (ayudante > 0) {
      lineas.add(LineaTarifa('Ayudante', ayudante, detalle: e.ayudante.label));
    }

    if (costoPisos > 0) {
      lineas.add(LineaTarifa(
        'Pisos y escaleras',
        costoPisos,
        detalle: '$pisos piso(s) × $viajes viaje(s)',
      ));
    }

    if (viajes > 1) {
      lineas.add(LineaTarifa(
        'Ajuste por varios viajes',
        costoViajes - subtotalViaje,
        detalle: '$viajes viajes · factor ${_pct(factorViajes)}',
      ));
    }

    return Tarifa(
      total: total,
      lineas: lineas,
      tipoCarga: tipoCarga,
      pesoKg: pesoKg,
      volumenM3: volumenM3,
      capacidadMinimaKg: categoria.capacidadMinKg,
      categoriaSugerida: categoria,
      esMudanza: esMudanza,
      viajes: viajes,
    );
  }

  /// Precio de la banda de distancia para carga rústica.
  ///
  /// Pasado [kmGratisAdicional] km suma [kmAdicional] por km extra.
  static double bandaDistancia(double km) {
    if (km.isNaN || km < 0) return bandasDistancia.first.value;
    for (final banda in bandasDistancia) {
      if (km <= banda.key) return banda.value;
    }
    final extra = km - kmGratisAdicional;
    return bandasDistancia.last.value + _redondear(extra * kmAdicional);
  }

  /// Categoría de motocarro más pequeña que cubre [pesoKg] con margen de
  /// seguridad. Si el peso no cabe en ninguna, devuelve la mayor.
  static CategoriaVehiculo categoriaParaPeso(double pesoKg) {
    for (final c in categoriasVehiculo) {
      if (c.cubre(pesoKg)) return c;
    }
    return categoriasVehiculo.last;
  }

  /// ¿Cubre este vehículo la carga? Compara contra la **capacidad autorizada**
  /// de ese vehículo concreto, no contra su cilindraje.
  static bool vehiculoCubre({
    required double pesoKg,
    required int capacidadAutorizadaKg,
  }) {
    if (capacidadAutorizadaKg <= 0) return false;
    return pesoKg <= capacidadAutorizadaKg * margenSeguridad;
  }

  // ── Internos ────────────────────────────────────────────────────────────

  static double _recargoArticulos(List<ArticuloSeleccionado> articulos) {
    var total = 0.0;
    for (final a in articulos) {
      total += a.recargoTotal;
    }
    return total;
  }

  /// 1 viaje → 1.00. 2 → 1.85. 3 → 2.65. n → 1.85 + 0.80·(n-2).
  static double _factorViajes(int viajes) {
    if (viajes <= 1) return 1.0;
    var f = 1.0 + factorSegundoViaje;
    for (var i = 3; i <= viajes; i++) {
      f += factorTercerViaje;
    }
    return f;
  }

  /// Redondea a miles de pesos: los precios se cobran enteros, no con
  /// decimales. "Aproximadamente $2.000 por km" deja margen para esto.
  static double _redondear(double v) {
    if (v.isNaN || v.isInfinite) return 0.0;
    if (v <= 0) return 0.0;
    return (v / 1000).round() * 1000.0;
  }

  static String _detalleBanda(double km) {
    if (km <= 6) return 'Hasta 6 km';
    if (km <= 10) return '6–10 km';
    if (km <= 15) return '10–15 km';
    if (km <= 20) return '15–20 km';
    if (km <= 25) return '20–25 km';
    return 'Más de 25 km';
  }

  static String _pct(double f) => '${(f * 100).toStringAsFixed(0)} %';
}
