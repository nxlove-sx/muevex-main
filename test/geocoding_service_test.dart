import 'package:flutter_test/flutter_test.dart';
import 'package:muevex/features/map/models/location_result.dart';

/// Pruebas del parseo de candidatos de Esri (`findAddressCandidates`).
///
/// Salen de respuestas reales del servicio (02/10/2026). Lo que se fija aquí
/// es lo que brokeaba la búsqueda de destinos: sin normalizar, ESRI devolvía
/// "Carrera" en Bogotá, "Colombia" o la misma esquina cinco veces, y el pin
/// caía en el sitio equivocado.
void main() {
  Map<String, dynamic> candidate({
    double? x,
    double? y,
    double score = 100,
    String address = '',
    Map<String, dynamic> attributes = const {},
  }) =>
      {
        'address': address,
        'location': {'x': x, 'y': y},
        'score': score,
        'attributes': attributes,
      };

  group('LocationResult.fromEsri', () {
    test('dirección con número: calle, barrio, ciudad y departamento', () {
      final r = LocationResult.fromEsri(candidate(
        x: -75.559216355498,
        y: 6.208796175826,
        address: 'Calle 10 30 20, Las Lomas No.1, Medellín, Antioquia',
        attributes: {
          'Match_addr': 'Calle 10 30 20, Las Lomas No.1, Medellín, Antioquia'
        },
      ));

      expect(r, isNotNull);
      // x=longitud, y=latitud: si se invirtieran, el pin caería en el mar.
      expect(r!.coordinates.latitude, closeTo(6.208796, 1e-6));
      expect(r.coordinates.longitude, closeTo(-75.559216, 1e-6));
      // La etiqueta del pin lleva calle + número.
      expect(r.name, 'Calle 10 30 20');
      expect(r.city, 'Medellín');
      expect(r.state, 'Antioquia');
      // Con calle el subtítulo sirve de confirmación, sin repetir el nombre.
      expect(r.street, 'Calle 10 30 20');
      expect(r.subtitle, 'Calle 10 30 20, Medellín, Antioquia');
    });

    test('Quita el país final y no lo mete en el subtítulo', () {
      final r = LocationResult.fromEsri(candidate(
        x: -75.8583,
        y: 8.7895,
        address: 'Carrera 3 12 40, Montería, Córdoba, Colombia',
        attributes: {
          'Match_addr': 'Carrera 3 12 40, Montería, Córdoba, Colombia'
        },
      ));

      expect(r!.city, 'Montería');
      expect(r.state, 'Córdoba');
      expect(r.subtitle, contains('Montería'));
      expect(r.subtitle, isNot(contains('Colombia')));
    });

    test('punto de interés sin calle: el subtítulo no repite el nombre', () {
      final r = LocationResult.fromEsri(candidate(
        x: -75.5709,
        y: 6.2675,
        address: 'Universidad de Antioquia, Medellín, Antioquia',
        attributes: {
          'Match_addr': 'Universidad de Antioquia, Medellín, Antioquia'
        },
      ));

      expect(r!.name, 'Universidad de Antioquia');
      expect(r.street, isNull);
      expect(r.subtitle, 'Medellín, Antioquia');
    });

    test('usa los campos sueltos de attributes cuando vienen', () {
      final r = LocationResult.fromEsri(candidate(
        x: -75.5713,
        y: 6.2070,
        address: 'algo',
        attributes: {
          'Match_addr': 'Carrera 43A 18-12, El Poblado, Medellín, Antioquia',
          'City': 'Medellín',
          'Region': 'Antioquia',
          'Postal': '050021',
        },
      ));

      expect(r!.city, 'Medellín');
      expect(r.state, 'Antioquia');
      expect(r.postcode, '050021');
    });

    test('descarta el score bajo ("Carrera", "Centro Comercial X")', () {
      // Lo que devuelve ESRI con la búsqueda a medio escribir: score 81-83 y
      // el nombre genérico de la vía, en la ciudad que le dé la gana.
      final carrera = LocationResult.fromEsri(candidate(
        x: -75.6905,
        y: 4.8135,
        score: 82.2,
        address: 'Carrera',
      ));
      expect(carrera, isNull);

      final centroComercial = LocationResult.fromEsri(candidate(
        x: -74.1081,
        y: 4.6264,
        score: 81.8,
        address: 'Centro Comercial Carrera',
      ));
      expect(centroComercial, isNull);

      // Una dirección real de Montería baja 93: no se descarta.
      final real = LocationResult.fromEsri(candidate(
        x: -75.8574,
        y: 8.8036,
        score: 93,
        address: 'Carrera 3 12 40, Montería, Córdoba',
        attributes: {'Match_addr': 'Carrera 3 12 40, Montería, Córdoba'},
      ));
      expect(real, isNotNull);
    });

    test('respeta el umbral de score que le pase el servicio', () {
      final r = LocationResult.fromEsri(
        candidate(x: -75.6, y: 6.2, score: 95, address: 'Carrera 70'),
        minScore: 99,
      );
      expect(r, isNull);
    });

    test('descarta el país y el departamento: no son destinos', () {
      expect(
        LocationResult.fromEsri(candidate(
          x: -73.0758,
          y: 3.9011,
          address: 'Colombia',
          attributes: {'Addr_type': 'Country'},
        )),
        isNull,
      );
      expect(
        LocationResult.fromEsri(candidate(
          x: -75.5636,
          y: 6.2442,
          address: 'Antioquia',
          attributes: {'Addr_type': 'State'},
        )),
        isNull,
      );
    });

    test('descarta coordenadas nulas o en Null Island', () {
      expect(
        LocationResult.fromEsri(candidate(
          x: 0,
          y: 0,
          address: 'Calle 10',
          attributes: {'Match_addr': 'Calle 10'},
        )),
        isNull,
      );
      expect(
        LocationResult.fromEsri(candidate(
          address: 'Calle 10',
          attributes: {'Match_addr': 'Calle 10'},
        )),
        isNull,
      );
    });

    test('descarta candidatos sin dirección legible', () {
      expect(
        LocationResult.fromEsri(candidate(x: -75.5, y: 6.2)),
        isNull,
      );
    });

    test('sin Match_addr cae al campo address plano', () {
      final r = LocationResult.fromEsri(candidate(
        x: -75.5707,
        y: 6.2073,
        address: 'Carrera 70, Medellín, Antioquia',
      ));

      expect(r!.name, 'Carrera 70');
      expect(r.city, 'Medellín');
    });
  });
}
