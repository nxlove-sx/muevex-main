/// Formato de moneda colombiana con separador de miles.
/// Ej.: money(25500) => "\$25.500"; money(-1200) => "\$-1.200".
///
/// El signo negativo va **después** del símbolo, no antes.
String money(double value) {
  final negative = value < 0;
  final s = value.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '\$${negative ? '-' : ''}$buf';
}

/// Tarifa de IVA de Colombia.
///
/// La tabla de TRANSPERSQUI da precios NETOS y el motor de tarifas
/// (`tariff_engine.dart`) no aplica IVA en ningún punto. Lo que el cliente ve
/// en la app es el subtotal; el IVA se suma al cobrar, tanto en la factura
/// (función `crear_factura_desde_servicio` de Postgres) como aquí.
///
/// > [!IMPORTANT] Un solo valor
/// > Este 19% está también en `public.emisor_config.iva_porcentaje` en
/// > Supabase. Si cambia la tarifa hay que cambiar los dos, o la app y la
/// > factura van a mostrar amounts distintos.
const double ivaRate = 0.19;

/// Precio que paga el cliente: el subtotal del motor más el IVA.
///
/// Usar esto en **todo** lugar donde se le muestre un precio al cliente como
/// "lo que vas a pagar". [money] a secas es para montos netos (subtotales,
/// desgloses, IVA por separado).
double precioTotalConIva(double subtotal) => subtotal * (1 + ivaRate);

/// Precio que paga el cliente, ya formateado.
String moneyConIva(double subtotal) => money(precioTotalConIva(subtotal));
