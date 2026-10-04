import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Tope de tiles guardados en memoria.
///
/// Cada tile decoded ocupa ~256 KB (256x256 px RGBA), así que 200 tiles son
/// ~50 MB: suficiente para cubrir con holgura la pantalla del mapa y sus
/// bordes de precarga, sin dejar el resto de la app sin memoria.
const int _kMaxMemoryTiles = 200;

/// Tope de espacio del caché en disco: 48 MB (unos miles de tiles).
const int _kMaxDiskBytes = 48 * 1024 * 1024;

/// Tiempo máximo de espera por un tile antes de darla por perdida.
const Duration _kTileTimeout = Duration(seconds: 12);

/// Caché de teselas de mapa en dos niveles (memoria + disco).
///
/// Por defecto `flutter_map` descarga cada tesela otra vez cada vez que se
/// vuelve a la pantalla del mapa. Con este caché:
///
///   - La segunda visita al mapa es **instantánea** (no hay esperas de red).
///   - Las zonas ya vistas **siguen funcionando sin cobertura**.
///
/// Se apoya solo en `path_provider` + `http`, que ya estaban en el proyecto,
/// para no arrastrar librerías de caché de mapas completas.
class MuevexTileCache {
  MuevexTileCache._();

  /// Instancia única. El caché es global a propósito: el cliente y el
  /// conductor (y cualquier otra pantalla con mapa) comparten teselas.
  static final MuevexTileCache instance = MuevexTileCache._();

  /// Bytes decodificados? No: guardamos los **bytes PNG**, que ocupan mucho
  /// menos que la imagen decodificada y se reutilizan tal cual.
  final Map<String, Uint8List> _memory = <String, Uint8List>{};

  /// Descargas en curso, para no pedir la misma tesela N veces a la vez cuando
  /// varias capas (base + referencia) piden la misma URL.
  final Map<String, Future<Uint8List>> _inFlight =
      <String, Future<Uint8List>>{};

  Directory? _diskDir;
  bool _diskPruned = false;

  /// Devuelve los bytes de la tesela, de memoria, de disco o de la red.
  ///
  /// Lanza la excepción del `http` si no se pudo obtener de ninguna parte, para
  /// que `TileLayer.errorTileCallback` la recoja y se pueda registrar.
  Future<Uint8List> fetch(String url) {
    final hit = _memory[url];
    if (hit != null) {
      // Devuelve un future ya resuelto: evita un frame de parpadeo al navegar
      // por una zona ya descargada.
      return SynchronousFuture<Uint8List>(hit);
    }
    return _inFlight.putIfAbsent(url, () => _load(url));
  }

  Future<Uint8List> _load(String url) async {
    try {
      // 1) Disco: sobrevive a reinicios de la app.
      final fromDisk = await _readDisk(url);
      if (fromDisk != null) {
        _remember(url, fromDisk);
        return fromDisk;
      }

      // 2) Red.
      final response = await http
          .get(Uri.parse(url), headers: kTileRequestHeaders)
          .timeout(_kTileTimeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw HttpException('Tesela $url -> HTTP ${response.statusCode}');
      }
      _remember(url, response.bodyBytes);
      // La escritura a disco no bloquea el pintado: si falla, se pierde el
      // caché pero el mapa sigue mostrando la tesela.
      unawaited(_writeDisk(url, response.bodyBytes));
      return response.bodyBytes;
    } finally {
      _inFlight.remove(url);
    }
  }

  // --- Memoria ---

  void _remember(String url, Uint8List bytes) {
    _memory[url] = bytes;
    if (_memory.length > _kMaxMemoryTiles) {
      // Se descarta la más antigua: el orden de inserción en un Map de Dart
      // es el orden de carga, así que basta con quitar la primera clave.
      _memory.remove(_memory.keys.first);
    }
  }

  // --- Disco ---

  Future<Directory> _dir() async {
    final existing = _diskDir;
    if (existing != null) return existing;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/muevex_tiles');
    if (!await dir.exists()) await dir.create(recursive: true);
    _diskDir = dir;
    return dir;
  }

  Future<Uint8List?> _readDisk(String url) async {
    try {
      final file = File('${(await _dir()).path}/${_hash(url)}.png');
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      // Un caché corrupto o sin permisos no debe romper el mapa.
      return null;
    }
  }

  Future<void> _writeDisk(String url, Uint8List bytes) async {
    try {
      final dir = await _dir();
      await File('${dir.path}/${_hash(url)}.png').writeAsBytes(
        bytes,
        flush: true,
      );
    } catch (_) {
      // Sin caché en disco, pero la tesela ya se pintó. No es un error fatal.
    }
  }

  /// Recorta el caché de disco una sola vez por sesión.
  Future<void> pruneDiskIfNeeded() async {
    if (_diskPruned) return;
    _diskPruned = true;
    try {
      final dir = await _dir();
      final files = <File>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          final size = await entity.length();
          total += size;
          files.add(entity);
        }
      }
      if (total <= _kMaxDiskBytes) return;
      // Los más antiguos primero (por fecha de modificación).
      files.sort(
          (a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      var excess = total - _kMaxDiskBytes;
      for (final file in files) {
        if (excess <= 0) break;
        final size = await file.length();
        await file.delete();
        excess -= size;
      }
    } catch (_) {
      // Poda best-effort: si falla, el caché simplemente crece.
    }
  }

  /// Hash **estable entre ejecuciones** (FNV-1a de 64 bits) para nombrar el
  /// fichero. `String.hashCode` de Dart no lo es, así que el caché en disco
  /// dejaría de encontrarse al reiniciar la app.
  String _hash(String url) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (var i = 0; i < url.length; i++) {
      hash ^= url.codeUnitAt(i) & 0xff;
      hash = (hash * prime) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Vacía el caché. Pensado para un botón de "recargar mapa" o para pruebas.
  void clearMemory() => _memory.clear();
}

/// Cabecera `User-Agent` de las peticiones de teselas.
///
/// Los servicios de teselas públicos (Esri) piden identificar al cliente; sin
/// esta cabecera puede que devuelvan 403 en lugar de la imagen.
///
/// NO es const: el constructor de `TileLayer` inyecta un `User-Agent` por
/// defecto con `headers.putIfAbsent(...)`, y un Map const no se puede
/// modificar. Una instanciación no const evita el fallo silencioso en build().
Map<String, String> kTileRequestHeaders = <String, String>{
  'User-Agent': 'MUEVEX/1.0 (Flutter; Android)',
};

/// Tesela de repuesto: un PNG sólido del color de fondo del mapa.
///
/// Se usa como `TileLayer.errorImage` para que un fallo de red no aparezca
/// como el icono de imagen rota de Flutter, que rompe la estética de la
/// pantalla. Al ser del mismo color que [kMapBackgroundColor] la zona sin
/// cargar se ve como un vacío oscuro y el resto del mapa sigue siendo legible.
///
/// Ojo: **no** lleva ningún patrón de diagnóstico. Este PNG es de 1x1 píxel
/// (69 bytes) y se escala a 256x256 al pintarse. Si algún día se quiere
/// distinguir a simple vista qué teselas fallaron, hay que generar el PNG con
/// un patrón de verdad, no describirlo aquí.
final ImageProvider kFallbackTileImage = MemoryImage(_generateFallbackTile());

/// Genera el PNG de 1x1 píxel que se usa como tesela de repuesto.
///
/// Los bytes van incrustados en lugar de generarse con `dart:ui` porque el
/// mapa también se ejecuta en tests y en la web, donde codificar un PNG en
/// tiempo de ejecución no es viable. Color: #141A2E, el fondo del mapa.
Uint8List _generateFallbackTile() {
  return Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    0x00,
    0x00,
    0x00,
    0x0d,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x5c,
    0x72,
    0xa8,
    0x66,
    0x00,
    0x00,
    0x05,
    0x19,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0xda,
    0xed,
    0xdd,
    0xb1,
    0x89,
    0xad,
    0x50,
    0x14,
    0x86,
    0x51,
    0x3b,
    0x30,
    0x31,
    0x32,
    0xb0,
    0x00,
    0x03,
    0x0b,
    0xb1,
    0x0d,
    0xfb,
    0xaf,
    0x41,
    0x31,
    0x10,
    0x4c,
    0x14,
    0xf6,
    0x41,
    0x3c,
    0xe8,
    0x5e,
    0xc1,
    0x79,
    0x30,
    0xd1,
    0x1a,
    0xee,
    0xef,
    0xfd,
    0xf0,
    0xc9,
    0x80,
    0x4d,
    0xbb,
    0xac,
    0xab,
    0xe3,
    0x38,
    0x39,
    0x4f,
    0xb3,
    0xff,
    0xd3,
    0xf5,
    0x53,
    0xb5,
    0x33,
    0x8c,
    0x33,
    0x9f,
    0xcf,
    0xaf,
    0x70,
    0x04,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x01,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x03,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x30,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x06,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x03,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x30,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x06,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0xb8,
    0x00,
    0xf8,
    0x7c,
    0x01,
    0xe0,
    0xf3,
    0xf9,
    0x02,
    0xc0,
    0xe7,
    0xf3,
    0x05,
    0x80,
    0xcf,
    0xe7,
    0x0b,
    0x00,
    0x9f,
    0xcf,
    0x17,
    0x00,
    0x3e,
    0x9f,
    0x2f,
    0x00,
    0x7c,
    0x3e,
    0x5f,
    0x00,
    0xf8,
    0x7c,
    0xbe,
    0x00,
    0xf0,
    0xf9,
    0x7c,
    0x01,
    0xe0,
    0xf3,
    0xf9,
    0x02,
    0xc0,
    0xe7,
    0xf3,
    0x05,
    0x80,
    0xcf,
    0xe7,
    0x0b,
    0x00,
    0x9f,
    0xcf,
    0x8f,
    0x07,
    0xc0,
    0xbb,
    0xd2,
    0x1d,
    0x27,
    0xdf,
    0x71,
    0x07,
    0xc0,
    0xe7,
    0xbb,
    0x03,
    0x10,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x30,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x06,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x03,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x70,
    0x01,
    0xf0,
    0xf9,
    0x02,
    0xc0,
    0xe7,
    0xf3,
    0x05,
    0x80,
    0xcf,
    0xe7,
    0x0b,
    0x00,
    0x9f,
    0xcf,
    0x17,
    0x00,
    0x3e,
    0x9f,
    0x2f,
    0x00,
    0x7c,
    0x3e,
    0x5f,
    0x00,
    0xf8,
    0x7c,
    0xbe,
    0x00,
    0xf0,
    0xf9,
    0x7c,
    0x01,
    0xe0,
    0xf3,
    0xf9,
    0x02,
    0xc0,
    0xe7,
    0xf3,
    0x05,
    0x80,
    0xcf,
    0xe7,
    0x0b,
    0x00,
    0x9f,
    0xcf,
    0x17,
    0x00,
    0x3e,
    0x9f,
    0x2f,
    0x00,
    0x7c,
    0x3e,
    0x5f,
    0x00,
    0xf8,
    0x7c,
    0x7e,
    0x3c,
    0x00,
    0xde,
    0x95,
    0xee,
    0x38,
    0xf9,
    0x8e,
    0x3b,
    0x00,
    0x3e,
    0xdf,
    0x1d,
    0x80,
    0x00,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x30,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x06,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x03,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x30,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x06,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x03,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x70,
    0x01,
    0xf0,
    0xf9,
    0x02,
    0xc0,
    0xe7,
    0xf3,
    0x05,
    0x80,
    0xcf,
    0xe7,
    0x0b,
    0x00,
    0x9f,
    0xcf,
    0x17,
    0x00,
    0x3e,
    0x9f,
    0x2f,
    0x00,
    0x7c,
    0x3e,
    0x5f,
    0x00,
    0xf8,
    0x7c,
    0xbe,
    0x00,
    0xf0,
    0xf9,
    0x7c,
    0x01,
    0xe0,
    0xf3,
    0xf9,
    0x02,
    0xc0,
    0xe7,
    0xf3,
    0x05,
    0x80,
    0xcf,
    0xe7,
    0x0b,
    0x00,
    0x9f,
    0xcf,
    0x17,
    0x00,
    0x3e,
    0x9f,
    0x1f,
    0x0f,
    0x80,
    0x77,
    0xa5,
    0x3b,
    0x4e,
    0xbe,
    0xe3,
    0x0e,
    0x80,
    0xcf,
    0x77,
    0x07,
    0x20,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x03,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x30,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x06,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x03,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x30,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x06,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x17,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x7c,
    0x3e,
    0x5f,
    0x00,
    0xf8,
    0x7c,
    0xbe,
    0x00,
    0xf0,
    0xf9,
    0x7c,
    0x01,
    0xe0,
    0xf3,
    0xf9,
    0x02,
    0xc0,
    0xe7,
    0xf3,
    0x05,
    0x80,
    0xcf,
    0xe7,
    0x0b,
    0x00,
    0x9f,
    0xcf,
    0x17,
    0x00,
    0x3e,
    0x9f,
    0x2f,
    0x00,
    0x7c,
    0x3e,
    0x5f,
    0x00,
    0xf8,
    0x7c,
    0xbe,
    0x00,
    0xf0,
    0xf9,
    0xfc,
    0x78,
    0x00,
    0xbc,
    0x2b,
    0xdd,
    0x71,
    0xf2,
    0x1d,
    0x77,
    0x00,
    0x7c,
    0xbe,
    0x3b,
    0x00,
    0x01,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x03,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x30,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x06,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0x18,
    0x80,
    0xcf,
    0x17,
    0x00,
    0x03,
    0xf0,
    0xf9,
    0x02,
    0x60,
    0x00,
    0x3e,
    0x5f,
    0x00,
    0x0c,
    0xc0,
    0xe7,
    0x0b,
    0x80,
    0x01,
    0xf8,
    0x7c,
    0x01,
    0x30,
    0x00,
    0x9f,
    0x2f,
    0x00,
    0x06,
    0xe0,
    0xf3,
    0x05,
    0xc0,
    0x00,
    0x7c,
    0xbe,
    0x00,
    0xb8,
    0x00,
    0xf8,
    0x7c,
    0x01,
    0xe0,
    0xf3,
    0xf9,
    0x02,
    0xc0,
    0xe7,
    0xf3,
    0x05,
    0x80,
    0xcf,
    0xe7,
    0x0b,
    0x00,
    0x9f,
    0xcf,
    0x17,
    0x00,
    0x3e,
    0x9f,
    0x2f,
    0x00,
    0x7c,
    0x3e,
    0x5f,
    0x00,
    0xf8,
    0x7c,
    0xbe,
    0x00,
    0xf0,
    0xf9,
    0x7c,
    0x01,
    0xe0,
    0xf3,
    0xf9,
    0x02,
    0xc0,
    0xe7,
    0xf3,
    0x8b,
    0x03,
    0xe0,
    0x38,
    0x4e,
    0xce,
    0xb3,
    0x01,
    0x6d,
    0x46,
    0xe1,
    0x7c,
    0x04,
    0x07,
    0xbf,
    0x73,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4e,
    0x44,
    0xae,
    0x42,
    0x60,
    0x82,
  ]);
}

/// `ImageProvider` que resuelve una tesela a través de [MuevexTileCache].
///
/// Flutter ya cachea en memoria cualquier `ImageProvider` por su clave, pero no
/// persiste en disco; este provider sí lo hace, y además sirve de clave estable
/// (`url`) para el `ImageCache` del framework.
class _MuevexTileImage extends ImageProvider<_MuevexTileImage> {
  const _MuevexTileImage(this.url);

  final String url;

  @override
  Future<_MuevexTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_MuevexTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _MuevexTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(decode),
      scale: 1,
      debugLabel: 'MuevexTile($url)',
    );
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await MuevexTileCache.instance.fetch(url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is _MuevexTileImage && other.url == url);

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'MuevexTile($url)';
}

/// [TileProvider] de MUEVEX: descarga con caché en memoria y disco.
///
/// Se pasa a `TileLayer.tileProvider`. Solo implementa [getImage], que es lo
/// único que `flutter_map` necesita cuando `supportsCancelLoading` es `false`.
class MuevexTileProvider extends TileProvider {
  MuevexTileProvider({Map<String, String>? headers}) : super(headers: headers);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _MuevexTileImage(getTileUrl(coordinates, options));
}

/// Proveedor de teselas compartido por todas las capas de mapa de la app.
final MuevexTileProvider kMuevexTileProvider = MuevexTileProvider(
  headers: kTileRequestHeaders,
);
