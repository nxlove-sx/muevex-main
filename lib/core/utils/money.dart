/// Formato de moneda colombiana con separador de miles.
/// Ej.: money(25500) => "\$25.500"; money(-1200) => "-\$1.200".
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