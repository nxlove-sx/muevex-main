/// Tests del motor de tarifas contra las reglas del documento de referencia.
///
/// El test más importante es [ejemplo oficial del documento], que reproduce
/// literalmente el caso que trae la propuesta: debe dar $80.000. Si ese test
/// falla, el motor no está implementando la especificación.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:muevex/core/services/tariff_engine.dart';

ArticuloSeleccionado art(String id, [int cantidad = 1]) => ArticuloSeleccionado(
      TarifaEngine.articuloPorId(id)!,
      cantidad,
    );

void main() {
  group('Ejemplo oficial del documento', () {
    // Nevera + TV de 55" + 5 cajas · 5 km · destino 3er piso sin ascensor ·
    // el cliente aporta persona para ayudar.
    //
    //   Tarifa de mudanza delicada: $50.000
    //   Recargo por pisos:         $30.000
    //   Ayudante:                   $0
    //   Distancia adicional:       $0
    //   TOTAL ESTIMADO:            $80.000
    test('da exactamente \$80.000', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 5,
        articulos: [art('nevera_mediana'), art('tv_55'), art('caja', 5)],
        pisosRecogida: 0,
        pisosEntrega: 3,
        ayudante: OrigenAyudante.cliente,
      ));

      expect(t.total, 80000);
      expect(t.tipoCarga, TipoCarga.delicada);
      expect(t.esMudanza, isTrue);
      expect(t.pesoKg, 80 + 18 + 100); // nevera + TV + 5 cajas
    });

    test('no cobra ayudante cuando lo aporta el cliente', () {
      final conCliente = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 5,
        articulos: [art('nevera_mediana'), art('tv_55')],
        pisosEntrega: 3,
        ayudante: OrigenAyudante.cliente,
      ));
      final conPlataforma = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 5,
        articulos: [art('nevera_mediana'), art('tv_55')],
        pisosEntrega: 3,
        ayudante: OrigenAyudante.plataforma,
      ));

      expect(conCliente.total, 80000);
      expect(conPlataforma.total, 110000); // + $30.000 del ayudante
    });
  });

  group('Punto 1 — banda de distancia, carga rústica', () {
    test('cada tramo da su tarifa', () {
      expect(TarifaEngine.bandaDistancia(0), 25000);
      expect(TarifaEngine.bandaDistancia(3), 25000);
      expect(TarifaEngine.bandaDistancia(6), 25000);
      expect(TarifaEngine.bandaDistancia(6.1), 30000);
      expect(TarifaEngine.bandaDistancia(10), 30000);
      expect(TarifaEngine.bandaDistancia(15), 35000);
      expect(TarifaEngine.bandaDistancia(20), 40000);
      expect(TarifaEngine.bandaDistancia(25), 45000);
    });

    test('más de 25 km suma \$2.000 por km adicional', () {
      expect(TarifaEngine.bandaDistancia(26), 47000);
      expect(TarifaEngine.bandaDistancia(30), 55000);
    });

    test('el mínimo de \$25.000 aplica desde cero (no \$5.000 + km)', () {
      // El PriceCalculator anterior daba $9.000 aquí. Este es el bug de fondo.
      final t = TarifaEngine.calcular(
        const TarifaEntrada(distanciaKm: 2, articulos: []),
      );
      expect(t.total, greaterThanOrEqualTo(25000));
      expect(t.total, 25000);
    });
  });

  group('Punto 2 — suelo de carga delicada', () {
    test('un solo electrodoméstico sube a \$40.000', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 2,
        articulos: [art('lavadora')],
      ));
      // El suelo de $40.000 es el mínimo, y el recargo del artículo va
      // "además de la tarifa base" (punto 3): 40.000 + 10.000 = 50.000.
      expect(t.total, 50000);
      expect(t.esMudanza, isFalse); // uno solo: no es mudanza conjunta
    });

    test('varios delicados suben a \$50.000', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 2,
        articulos: [art('lavadora'), art('nevera_pequena')],
      ));
      expect(t.total, 50000);
      expect(t.esMudanza, isTrue);
    });

    test('la banda larga puede superar el suelo', () {
      // 30 km con un solo electrodoméstico: manda la distancia, no el mínimo.
      // 45.000 + 5 km extra × 2.000 = 55.000, más 10.000 del recargo.
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 30,
        articulos: [art('lavadora')],
      ));
      expect(t.total, 65000);
    });
  });

  group('Punto 3 — los recargos no se suman en una mudanza', () {
    test('varios artículos no acumulan sus recargos', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 4,
        articulos: [art('colchon_doble'), art('closet_armado')],
      ));
      // Suma de recargos sería 10.000 + 20.000 = 30.000 por encima del suelo.
      // Al ser mudanza conjunta, la base sigue siendo $50.000.
      expect(t.total, 50000);
    });

    test('un solo artículo sí paga su recargo', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 4,
        articulos: [art('closet_armado')],
      ));
      // $40.000 de suelo delicado + $20.000 de recargo.
      expect(t.total, 60000);
    });

    test('la cantidad de un artículo sí multiplica su recargo', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 4,
        articulos: [art('espejo_vitrina', 2)],
      ));
      // Un solo tipo de artículo → no es mudanza: 40.000 + 2×20.000.
      expect(t.total, 80000);
    });
  });

  group('Punto 4 — pisos y escaleras', () {
    test('\$10.000 por piso, y por viaje', () {
      final unViaje = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 3,
        pisosEntrega: 2,
      ));
      expect(unViaje.total, 25000 + 20000);

      final tresViajes = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 3,
        pisosEntrega: 2,
        viajes: 3,
      ));
      // Pisos ×3 viajes = 6 pisos × 10.000 = 60.000.
      final recargoPisos = tresViajes.lineas
          .firstWhere((l) => l.concepto == 'Pisos y escaleras');
      expect(recargoPisos.monto, 60000);
    });

    test('recogida y entrega se suman', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 3,
        pisosRecogida: 4,
        pisosEntrega: 2,
      ));
      expect(t.total, 25000 + 60000);
    });

    test('los pisos no reciben el descuento de varios viajes', () {
      // El descuento del 2º viaje es sobre el costo del viaje, no sobre los
      // pisos: reducir los pisos dos veces cobraría de menos.
      final conPisos = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 3,
        pisosEntrega: 1,
        viajes: 2,
      ));
      final linea =
          conPisos.lineas.firstWhere((l) => l.concepto == 'Pisos y escaleras');
      expect(linea.monto, 20000); // 1 piso × 10.000 × 2 viajes, sin descuento
    });
  });

  group('Punto 5 — ayudante', () {
    test('la plataforma cobra \$30.000', () {
      final t = TarifaEngine.calcular(const TarifaEntrada(
        distanciaKm: 3,
        ayudante: OrigenAyudante.plataforma,
      ));
      expect(t.total, 55000);
    });

    test('el incluido no cuesta nada', () {
      final t = TarifaEngine.calcular(const TarifaEntrada(distanciaKm: 3));
      expect(t.total, 25000);
    });
  });

  group('Punto 6 — varios viajes', () {
    test('el 2º viaje suma 85 % y el 3º en adelante 80 %', () {
      final v1 = TarifaEngine.calcular(const TarifaEntrada(distanciaKm: 5));
      final v2 =
          TarifaEngine.calcular(const TarifaEntrada(distanciaKm: 5, viajes: 2));
      final v3 =
          TarifaEngine.calcular(const TarifaEntrada(distanciaKm: 5, viajes: 3));
      final v4 =
          TarifaEngine.calcular(const TarifaEntrada(distanciaKm: 5, viajes: 4));

      expect(v1.total, 25000);
      // El 2º viaje añade 85 % de 25.000 = 21.250, y el total se redondea a
      // miles: 46.250 → 46.000.
      expect(v2.total, 46000);
      expect(v3.total, 25000 + 21000 + 20000); // 66.000
      expect(v4.total, 25000 + 21000 + 20000 + 20000); // 86.000
    });

    test('viajes 0 o negativos se tratan como 1', () {
      expect(
        TarifaEngine.calcular(const TarifaEntrada(distanciaKm: 5, viajes: 0))
            .total,
        25000,
      );
      expect(
        TarifaEngine.calcular(const TarifaEntrada(distanciaKm: 5, viajes: -3))
            .total,
        25000,
      );
    });
  });

  group('Punto 7 — vehículo por capacidad autorizada, no por cilindraje', () {
    test('cada franja de peso pide la categoría correcta', () {
      expect(TarifaEngine.categoriaParaPeso(100).cc, 200);
      expect(TarifaEngine.categoriaParaPeso(400).cc, 200);
      expect(TarifaEngine.categoriaParaPeso(600).cc, 250);
      expect(TarifaEngine.categoriaParaPeso(900).cc, 300);
      expect(TarifaEngine.categoriaParaPeso(1200).cc, 500);
    });

    test('el margen de seguridad impide_FULL la sobrecarga', () {
      // El motocarro 200 declara hasta 510 kg, pero solo se usan el 90 %.
      expect(TarifaEngine.categoriaParaPeso(459).cc, 200);
      expect(TarifaEngine.categoriaParaPeso(460).cc, 250);
    });

    test('un peso enorme cae en la categoría mayor, no revienta', () {
      expect(TarifaEngine.categoriaParaPeso(99999).cc, 500);
    });

    test('vehiculoCubre compara contra la capacidad de ESE vehículo', () {
      // Dos motocarros de 300 cc: uno autorizado para 800 kg y otro para 1000.
      // La app debe decidir por el campo de capacidad, no por el cilindraje.
      expect(
        TarifaEngine.vehiculoCubre(pesoKg: 700, capacidadAutorizadaKg: 800),
        isTrue,
      );
      expect(
        TarifaEngine.vehiculoCubre(pesoKg: 700, capacidadAutorizadaKg: 1000),
        isTrue,
      );
      expect(
        TarifaEngine.vehiculoCubre(pesoKg: 900, capacidadAutorizadaKg: 800),
        isFalse,
      );
      expect(
        TarifaEngine.vehiculoCubre(pesoKg: 100, capacidadAutorizadaKg: 0),
        isFalse,
      );
    });

    test('el peso total de los artículos decide el vehículo', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 3,
        articulos: [art('closet_armado'), art('trompo')],
      ));
      // 160 + 110 = 270 kg → entra en el motocarro 200.
      expect(t.pesoKg, 270);
      expect(t.categoriaSugerida.cc, 200);
      expect(t.capacidadMinimaKg, 410);
    });
  });

  group('Entradas degeneradas', () {
    test('sin artículos y sin pisos devuelve la carrera mínima', () {
      final t = TarifaEngine.calcular(const TarifaEntrada(distanciaKm: 1));
      expect(t.total, 25000);
      expect(t.pesoKg, 0);
      expect(t.tipoCarga, TipoCarga.rustica);
    });

    test('distancia NaN o negativa no rompe el cálculo', () {
      expect(
          TarifaEngine.calcular(const TarifaEntrada(distanciaKm: double.nan))
              .total,
          25000);
      expect(TarifaEngine.calcular(const TarifaEntrada(distanciaKm: -10)).total,
          25000);
    });

    test('pisos negativos se tratan como 0', () {
      final t = TarifaEngine.calcular(const TarifaEntrada(
        distanciaKm: 3,
        pisosRecogida: -2,
        pisosEntrega: -5,
      ));
      expect(t.total, 25000);
    });

    test('cantidad 0 de un artículo no aporta ni peso ni recargo', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 3,
        articulos: [
          ArticuloSeleccionado(TarifaEngine.articuloPorId('lavadora')!, 0)
        ],
      ));
      expect(t.pesoKg, 0);
      expect(t.total, 25000);
    });
  });

  group('Desglose', () {
    // ── El invariante ──────────────────────────────────────────────────
    //
    // "El total siempre coincide con la suma de las líneas" estaba probado, pero
    // **solo con un caso de mudanza** (sofá + nevera = 2 artículos delicados), y
    // en mudanza los recargos van dentro de la base, así que el descuadre no se
    // veía. Estos tests barren los casos que sí lo tenían roto.

    test('el total coincide con la suma de las líneas (caso de mudanza)', () {
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 12,
        articulos: [art('sofa_3'), art('nevera_pequena')],
        pisosRecogida: 2,
        pisosEntrega: 3,
        ayudante: OrigenAyudante.plataforma,
        viajes: 2,
      ));
      // Las líneas de ajuste van con monto negativo a propósito, así que la
      // suma tiene que ser exacta, no "mayor que".
      final suma = t.lineas.fold<double>(0, (s, l) => s + l.monto);
      expect(suma, t.total);
    });

    test('un solo artículo NO duplica su recargo en las líneas', () {
      // Una lavadora sola: suelo delicado $40.000 + recargo $10.000 = $50.000.
      // La línea de la base tiene que decir $40.000, no $50.000, porque el
      // recargo ya viene en su propia línea. Antes las dos cosas se pintaban y
      // el desglose sumaba $60.000 sobre un total de $50.000.
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 4,
        articulos: [art('lavadora')],
      ));

      expect(t.total, 50000);
      final base =
          t.lineas.firstWhere((l) => l.concepto.contains('carga delicada'));
      expect(base.monto, 40000);
      final recargo =
          t.lineas.firstWhere((l) => l.concepto.contains('Recargos'));
      expect(recargo.monto, 10000);

      final suma = t.lineas.fold<double>(0, (s, l) => s + l.monto);
      expect(suma, t.total);
    });

    test('varios viajes: el reparto no se descuadra con el redondeo', () {
      // 1,85 × $50.000 = $92.500 exactos, y el total redondeado a miles era
      // $93.000: las líneas sumaban $92.500. El total sigue siendo $93.000; lo
      // que cambia es cómo se reparte, que es lo único que puede cambiar sin
      // tocar el precio que se le cobra a la gente.
      final t = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 8,
        articulos: [art('sofa_3'), art('nevera_mediana')],
        viajes: 2,
      ));

      expect(t.total, 93000);
      final suma = t.lineas.fold<double>(0, (s, l) => s + l.monto);
      expect(suma, t.total);
    });

    test('el invariante se cumple en toda la matriz, no solo en un caso', () {
      // Barrido completo. Con el motor roto, 38.556 de estos 52.272 casos
      // descuadraban, con diferencias de hasta $20.450.
      final ids = TarifaEngine.catalogo.map((a) => a.id).toList();
      const distancias = [
        0.0,
        1.5,
        4.0,
        6.0,
        9.9,
        12.0,
        18.0,
        24.5,
        25.0,
        31.0,
        47.3
      ];
      const pisos = [0, 1, 3];
      const viajes = [1, 2, 3, 4];
      const ayudantes = [
        OrigenAyudante.incluido,
        OrigenAyudante.cliente,
        OrigenAyudante.plataforma,
      ];

      var casos = 0;
      final descuadres = <String>[];

      for (final id in ids) {
        for (final km in distancias) {
          for (final pr in pisos) {
            for (final pe in pisos) {
              for (final v in viajes) {
                for (final ay in ayudantes) {
                  for (final cuantos in [1, 3]) {
                    final arts = <ArticuloSeleccionado>[art(id)];
                    if (cuantos == 3) {
                      arts.addAll([art('lavadora'), art('caja', 2)]);
                    }
                    final t = TarifaEngine.calcular(TarifaEntrada(
                      distanciaKm: km,
                      articulos: arts,
                      pisosRecogida: pr,
                      pisosEntrega: pe,
                      ayudante: ay,
                      viajes: v,
                    ));
                    casos++;
                    final suma =
                        t.lineas.fold<double>(0, (s, l) => s + l.monto);
                    if ((suma - t.total).abs() > 0.001) {
                      descuadres.add('$id km=$km pisos=$pr/$pe viajes=$v '
                          '${ay.name} n=$cuantos: suma=$suma total=${t.total}');
                    }
                  }
                }
              }
            }
          }
        }
      }

      expect(casos, 52272);
      expect(descuadres, isEmpty);
    });

    test('siempre hay al menos la línea de tarifa base', () {
      final t = TarifaEngine.calcular(const TarifaEntrada(distanciaKm: 7));
      expect(t.lineas, isNotEmpty);
      expect(t.lineas.first.detalle, '6–10 km');
    });
  });

  group('Catálogo', () {
    test('los ids son únicos', () {
      final ids = TarifaEngine.catalogo.map((a) => a.id).toSet();
      expect(ids.length, TarifaEngine.catalogo.length);
    });

    test('todo artículo tiene peso y volumen razonables', () {
      for (final a in TarifaEngine.catalogo) {
        expect(a.pesoKg, greaterThan(0), reason: a.id);
        expect(a.volumenM3, greaterThan(0), reason: a.id);
        expect(a.nombre, isNotEmpty, reason: a.id);
      }
    });

    test('articuloPorId encuentra y descarta bien', () {
      expect(TarifaEngine.articuloPorId('lavadora')?.nombre, 'Lavadora');
      expect(TarifaEngine.articuloPorId('no_existe'), isNull);
    });

    test('los recargos coinciden con la tabla del documento', () {
      // Subconjunto de la sección 3, para detectar cualquier cambio accidental.
      const esperado = {
        'colchon_sencillo': 5000,
        'colchon_doble': 10000,
        'cama_desarmada': 10000,
        'sofa_2': 10000,
        'sofa_3': 15000,
        'comedor': 15000,
        'closet_desarmado': 10000,
        'closet_armado': 20000,
        'lavadora': 10000,
        'nevera_pequena': 15000,
        'nevera_mediana': 20000,
        'tv_43': 10000,
        'tv_55': 15000,
        'tv_70': 20000,
        'aire_acondicionado': 10000,
        'espejo_vitrina': 20000,
        'trompo': 15000,
        'rana': 15000,
      };
      esperado.forEach((id, recargo) {
        expect(TarifaEngine.articuloPorId(id)?.recargo, recargo, reason: id);
      });
    });
  });
}
