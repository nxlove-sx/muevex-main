/// Tests del IVA y del formato de moneda.
///
/// La tabla de TRANSPERSQUI da precios **netos**: el motor de tarifas no aplica
/// IVA en ningún punto. Lo que el cliente ve en la app es el subtotal, y el IVA
/// se suma al cobrar, tanto en el desglose como en la factura.
///
/// Estos tests fijan ese comportamiento porque el error sería silencioso: si el
/// IVA se aplicara dos veces, o se aplicara al revés, las cifras no darían error
/// de compilación, solo facturas con un 19% de más o de menos.
///
/// Ojo: el 19% está duplicado entre este fichero y
/// `public.emisor_config.iva_porcentaje` en Supabase. Si cambia la tarifa hay
/// que cambiar los dos, o la app y la factura mostraran amounts distintos.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:muevex/core/services/tariff_engine.dart';
import 'package:muevex/core/utils/money.dart';

void main() {
  group('money: formato colombiano', () {
    test('separa los miles con punto', () {
      expect(money(25500), '\$25.500');
      expect(money(80000), '\$80.000');
      expect(money(1234567), '\$1.234.567');
    });

    test('los miles exactos no llevan separador al inicio', () {
      expect(money(1000), '\$1.000');
      expect(money(1000000), '\$1.000.000');
    });

    test('los negativos llevan el signo después del símbolo', () {
      // Ojo: el signo va DESPUÉS del símbolo, `$-1.200`. Es lo que hace la
      // función y lo que espera el resto de la app; el docstring decía otra
      // cosa y por eso este test. Si algún día se cambia el orden del signo,
      // hay que cambiar también lo que haya en las pantallas.
      expect(money(-1200), '\$-1.200');
    });

    test('redondea al peso, sin decimales', () {
      expect(money(25500.4), '\$25.500');
      expect(money(25500.6), '\$25.501');
    });
  });

  group('IVA: los precios del motor son netos', () {
    test('el total con IVA es un 19% más que el subtotal', () {
      expect(precioTotalConIva(80000), closeTo(95200, 0.001));
    });

    test('el IVA es exactamente la diferencia entre el total y el subtotal',
        () {
      const subtotal = 80000.0;
      final iva = precioTotalConIva(subtotal) - subtotal;
      expect(iva, closeTo(15200, 0.001));
      expect(iva / subtotal, closeTo(0.19, 0.0001));
    });

    test('un subtotal de 0 sigue dando 0, no NaN ni negativo', () {
      expect(precioTotalConIva(0), 0);
    });

    test('moneyConIva formatea el total, no el subtotal', () {
      // 80.000 netos -> 95.200 con IVA. Si alguna vez devolviera 80.000 sería
      // que se está mostrando el subtotal como si fuera el total.
      expect(moneyConIva(80000), '\$95.200');
    });
  });

  group('IVA aplicado sobre un caso real del motor', () {
    // El mismo escenario del ejemplo del documento, para comprobar que la
    // cadena completa funciona: motor -> neto -> total facturado.
    test('el total facturado es el 19% del precio que cotizó el motor', () {
      final tarifa = TarifaEngine.calcular(const TarifaEntrada(
        distanciaKm: 5,
        pisosEntrega: 3,
      ));

      // Lo que el motor produce es el subtotal: sin IVA.
      final facturado = precioTotalConIva(tarifa.total);
      expect(facturado, greaterThan(tarifa.total));
      expect(facturado / tarifa.total, closeTo(1.19, 0.0001));
    });

    test('el ejemplo del documento: 80.000 netos facturan 95.200', () {
      final tarifa = TarifaEngine.calcular(TarifaEntrada(
        distanciaKm: 5,
        articulos: [
          ArticuloSeleccionado(
              TarifaEngine.articuloPorId('nevera_mediana')!, 1),
          ArticuloSeleccionado(TarifaEngine.articuloPorId('tv_55')!, 1),
          ArticuloSeleccionado(TarifaEngine.articuloPorId('caja')!, 5),
        ],
        pisosEntrega: 3,
        ayudante: OrigenAyudante.cliente,
      ));

      // El motor da 80.000. Ese es el subtotal.
      expect(tarifa.total, 80000);
      // Lo que se factura es un 19% más.
      expect(moneyConIva(tarifa.total), '\$95.200');
    });
  });
}
