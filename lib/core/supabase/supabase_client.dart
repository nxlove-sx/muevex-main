import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:muevex/core/models/user_model.dart' as muevex_user;
import 'package:muevex/core/models/customer_profile_model.dart';
import 'package:muevex/core/models/service_model.dart';
import 'package:muevex/core/models/payment_model.dart';
import 'package:muevex/core/models/rating_model.dart';
import 'package:muevex/core/models/notification_model.dart';
import 'package:muevex/core/models/invoice_model.dart';
import 'package:muevex/core/supabase/supabase_config.dart';

late final SupabaseClient supabase;

class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: persistSessionKey);

  @override
  Future<String?> accessToken() => _storage.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() =>
      _storage.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: persistSessionKey, value: persistSessionString);
}

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    publishableKey: SupabaseConfig.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      // Sesión en almacenamiento cifrado (flutter_secure_storage).
      localStorage: SecureLocalStorage(
        persistSessionKey:
            'sb-${Uri.parse(SupabaseConfig.supabaseUrl).host.split('.').first}-auth-token',
      ),
    ),
  );
  supabase = Supabase.instance.client;
}

// Auth helpers
User? getCurrentUser() {
  final authUser = supabase.auth.currentUser;
  return authUser;
}

/// true si hay una sesión viva (se usa en splash/router para no volver a /login).
bool get authed => supabase.auth.currentSession != null;

Stream<User?> authStateChanges() {
  return supabase.auth.onAuthStateChange.map((event) {
    return event.session?.user;
  });
}

// User profile helpers
Future<muevex_user.User> getUserProfile(String userId) async {
  final res = await supabase.from('users').select().eq('id', userId).single();
  return muevex_user.User.fromMap(res);
}

// Customer profile
Future<CustomerProfile> getCustomerProfile(String userId) async {
  final res = await supabase
      .from('customer_profiles')
      .select()
      .eq('user_id', userId)
      .single();
  return CustomerProfile.fromMap(res);
}

// Service operations
/// Inserta la solicitud con el estado canónico 'solicitado' y los campos del spec.
Future<Service> createService(Service service) async {
  final res = await supabase
      .from('services')
      .insert({
        'customer_id': service.customerId,
        'status': 'solicitado',
        'price_base':
            service.priceBase > 0 ? service.priceBase : service.estimatedPrice,
        'price_recommended': service.recommendedPrice,
        'price_offer': service.priceOffer,
        'estimated_price': service.estimatedPrice,
        'platform_fee': 0,
        'origin_lat': service.originLat,
        'origin_lng': service.originLng,
        'destination_lat': service.destinationLat,
        'destination_lng': service.destinationLng,
        'origin_name': service.originName,
        'destination_name': service.destinationName,
        'origin': service.origin,
        'destination': service.destination,
        'description': service.description,
        'load_description': service.loadDescription,
        'distance_km': service.distanceKm,
        'estimated_time_min': service.estimatedTimeMin.round(),
        'duration_minutes': service.durationMinutes,
        'load_type': service.loadType,
        'load_weight_kg': service.loadWeightKg,
        'floors': service.floors,
        'loading_help': service.loadingHelp,
        'photos': service.photos,
        // Tarifas v2
        'items': service.items,
        'floors_pickup': service.floorsPickup,
        'floors_delivery': service.floorsDelivery,
        'trips': service.trips,
        'helper_origin': service.helperOrigin,
        'estimated_weight_kg': service.estimatedWeightKg,
        'estimated_volume_m3': service.estimatedVolumeM3,
        'vehicle_category': service.vehicleCategory,
        'tariff_breakdown': service.tariffBreakdown,
        'tariff_version': service.tariffVersion,
      })
      .select()
      .single();
  return Service.fromMap(res);
}

/// Crea la solicitud y sube las fotos a Storage (`service-loads/{id}/`).
Future<Service> createServiceWithPhotos(
  Service service,
  List<String> photoPaths,
) async {
  final created = await createService(service.copyWith(photos: const []));
  if (photoPaths.isEmpty) return created;

  final urls = await uploadServicePhotos(created.id, photoPaths);
  if (urls.isEmpty) return created;

  try {
    final res = await supabase
        .from('services')
        .update({'photos': urls})
        .eq('id', created.id)
        .select()
        .single();
    return Service.fromMap(res);
  } catch (_) {
    return created;
  }
}

/// Sube fotos de la carga al bucket `service-loads/{serviceId}/`.
Future<List<String>> uploadServicePhotos(
  String serviceId,
  List<String> photoPaths,
) async {
  final urls = <String>[];
  for (var i = 0; i < photoPaths.length; i++) {
    final path = photoPaths[i];
    final file = File(path);
    if (!await file.exists()) continue;
    // Limite del bucket service-loads: 10 MB. Se omite lo que lo supere.
    if (await file.length() > 10 * 1024 * 1024) continue;
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : 'jpg';
    final safeExt = const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(ext)
        ? ext
        : 'jpg';
    final name =
        'foto_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final objectPath = '$serviceId/$name';
    try {
      await supabase.storage.from('service-loads').upload(
            objectPath,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
      urls.add(supabase.storage.from('service-loads').getPublicUrl(objectPath));
    } catch (_) {}
  }
  return urls;
}

Future<List<Service>> getUserServices(String userId) async {
  final res = await supabase
      .from('services')
      .select()
      .eq('customer_id', userId)
      .order('created_at', ascending: false);
  return (res as List).map((e) => Service.fromMap(e)).toList();
}

Future<Service> getServiceById(String serviceId) async {
  final res =
      await supabase.from('services').select().eq('id', serviceId).single();
  return Service.fromMap(res);
}

Future<Service> cancelService(String serviceId) async {
  final res = await supabase.rpc(
    'cancel_service',
    params: {'p_service_id': serviceId, 'p_cancelled_by': 'cliente'},
  );
  final rows = (res as List?) ?? <dynamic>[];
  if (rows.isEmpty) {
    throw StateError('No se pudo cancelar el servicio.');
  }
  return Service.fromMap(rows.first as Map<String, dynamic>);
}

// Track del conductor (driver_locations, columna real)
Future<Map<String, dynamic>?> getDriverLocation(String driverId) async {
  final res = await supabase
      .from('driver_locations')
      .select('latitude,longitude,updated_at')
      .eq('driver_id', driverId)
      .order('updated_at', ascending: false)
      .limit(1)
      .maybeSingle();
  return res == null ? null : Map<String, dynamic>.from(res);
}

/// Datos de la tarjeta del conductor asignado (permitidos por RLS del spec 55).
class DriverCardInfo {
  final String name;
  final String? phone;
  final double rating;
  final String? photoUrl;
  final String? licenseNumber;
  final bool isVerified;
  final String? plate;
  final String? vehicleType;
  final String? brand;
  final String? model;
  final int capacityKg;

  const DriverCardInfo({
    required this.name,
    this.phone,
    this.rating = 0,
    this.photoUrl,
    this.licenseNumber,
    this.isVerified = false,
    this.plate,
    this.vehicleType,
    this.brand,
    this.model,
    this.capacityKg = 0,
  });

  bool get hasVehicle => plate?.isNotEmpty == true;

  /// Etiqueta legible del tipo de vehículo (ej. "motocarro" → "Motocarro").
  String get vehicleTypeLabel {
    final raw = vehicleType ?? '';
    if (raw.isEmpty) return '';
    const names = {
      'motocarro': 'Motocarro',
      'moto': 'Moto',
      'camion': 'Camión',
      'camioneta': 'Camioneta',
      'furgon': 'Furgón',
      'van': 'Van',
      'taxi': 'Taxi',
      'carro': 'Carro',
    };
    if (names.containsKey(raw.toLowerCase())) {
      return names[raw.toLowerCase()]!;
    }
    final first = raw[0].toUpperCase();
    return '$first${raw.substring(1)}';
  }
}

Future<DriverCardInfo?> getDriverCard(String driverId) async {
  try {
    final userRes = await supabase
        .from('users')
        .select('name,phone')
        .eq('id', driverId)
        .maybeSingle();
    final profileRes = await supabase
        .from('driver_profiles')
        .select('rating,photo_url,license_number,is_verified')
        .eq('user_id', driverId)
        .maybeSingle();
    Map<String, dynamic>? vehicleRes;
    try {
      final v = await supabase
          .from('vehicles')
          .select('plate,type,brand,model,capacity_kg')
          .eq('driver_id', driverId)
          .limit(1)
          .maybeSingle();
      vehicleRes = v == null ? null : Map<String, dynamic>.from(v);
    } catch (_) {
      vehicleRes = null;
    }

    return DriverCardInfo(
      name: userRes?['name'] as String? ?? 'Conductor',
      phone: userRes?['phone'] as String?,
      rating: (profileRes?['rating'] as num?)?.toDouble() ?? 0,
      photoUrl: profileRes?['photo_url'] as String?,
      licenseNumber: profileRes?['license_number'] as String?,
      isVerified: (profileRes?['is_verified'] as bool?) ?? false,
      plate: vehicleRes?['plate'] as String?,
      vehicleType: (vehicleRes?['type'] as String?) ??
          (vehicleRes?['vehicle_type'] as String?),
      brand: vehicleRes?['brand'] as String?,
      model: vehicleRes?['model'] as String?,
      capacityKg: (vehicleRes?['capacity_kg'] as num?)?.toInt() ?? 0,
    );
  } catch (_) {
    return null;
  }
}

// Payment operations

/// Indica si el servicio ya tiene un pago registrado (evita insertar
/// pagos duplicados si el usuario toca "Pagar" dos veces).
Future<bool> paymentExists(String serviceId) async {
  try {
    final res = await supabase
        .from('payments')
        .select('id')
        .eq('service_id', serviceId)
        .limit(1)
        .maybeSingle();
    return res != null;
  } catch (_) {
    return false;
  }
}

bool authLoaded() => supabase.auth.currentSession != null;

/// Cambia la contraseña verificando primero la actual (contraseña actual
/// del usuario logueado). Devuelve false si la actual no es válida.
Future<bool> changePassword({
  required String currentPassword,
  required String newPassword,
}) async {
  final email = supabase.auth.currentUser?.email;
  if (email == null) return false;
  try {
    final res = await supabase.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    if (res.user == null) return false;
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
    return true;
  } catch (_) {
    return false;
  }
}

Future<Payment> createPayment(Payment payment) async {
  final res =
      await supabase.from('payments').insert(payment.toMap()).select().single();
  return Payment.fromMap(res);
}

// Rating operations
Future<Rating> createRating(Rating rating) async {
  final res =
      await supabase.from('ratings').insert(rating.toMap()).select().single();
  return Rating.fromMap(res);
}

// Notification operations
Future<AppNotification> createNotification(AppNotification notification) async {
  final res = await supabase
      .from('notifications')
      .insert(notification.toMap())
      .select()
      .single();
  return AppNotification.fromMap(res);
}

Future<List<AppNotification>> getMyNotifications(String userId) async {
  final res = await supabase
      .from('notifications')
      .select()
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(50);
  return (res as List).map((e) => AppNotification.fromMap(e)).toList();
}

/// Marca todas las notificaciones del usuario como leídas. La política
/// `notifications_update_own` restringe la fila a su propio `user_id`.
Future<void> markAllNotificationsRead(String userId) async {
  await supabase
      .from('notifications')
      .update({'read': true})
      .eq('user_id', userId)
      .eq('read', false);
}

/// Registro simple de una coordenada geográfica (latitud/longitud).
class LatLngRecord {
  final double latitude;
  final double longitude;

  const LatLngRecord({required this.latitude, required this.longitude});
}

/// Resultado de [submitClientRating].
///
/// Existía un `bool` y eso obligaba a la UI a inventar el motivo del fallo: el
/// mismo "ya calificaste este servicio" salía cuando lo que había pasado era un
/// 403 de RLS, la sesión caducada o la red caída. Un mensaje genérico que no
/// distingue "no puedes" de "ya lo hiciste" es el peor sitio donde perder el
/// tiempo, así que el motivo viaja con el resultado.
typedef RatingSubmitResult = ({
  bool ok,
  bool alreadyRated,
  String? error,
});

/// Traduce un fallo de Postgres a algo sobre lo que un usuario pueda actuar.
///
/// El mensaje crudo se registra aparte: al usuario se le dice qué hacer, al log
/// se le deja el detalle técnico.
String _ratingErrorMessage(Object e) {
  if (e is PostgrestException) {
    switch (e.code) {
      case '42501':
        return 'Tu cuenta no tiene permiso para calificar este servicio.';
      case '23503':
        return 'No encontramos el servicio o el conductor. Actualiza e '
            'inténtalo de nuevo.';
      case 'PGRST116':
      case 'PGRST301':
        return 'Tu sesión expiró. Vuelve a entrar e inténtalo de nuevo.';
      default:
        return 'No se pudo guardar la calificación. Inténtalo de nuevo.';
    }
  }
  return 'No se pudo guardar la calificación. Revisa tu conexión.';
}

/// Envía la calificación del cliente al conductor.
///
/// Requiere que el servicio esté completado y que el cliente sea el dueño.
/// Nunca lanza: cualquier fallo vuelve dentro de [RatingSubmitResult] con el
/// motivo, para que quien llama pueda quitar el spinner de "enviando" y decir
/// algo cierto en vez de dejar el botón muerto.
Future<RatingSubmitResult> submitClientRating({
  required String serviceId,
  required String driverId,
  required double score, // 1..5
  String? comment,
}) async {
  final user = supabase.auth.currentUser;
  if (user == null) {
    return (
      ok: false,
      alreadyRated: false,
      error: 'Tu sesión expiró. Vuelve a entrar e inténtalo de nuevo.',
    );
  }

  try {
    await supabase.from('ratings').insert({
      'service_id': serviceId,
      'rater_id': user.id,
      'rated_id': driverId,
      'score': score,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    });
    return (ok: true, alreadyRated: false, error: null);
  } on PostgrestException catch (e) {
    // 23505 = unique_violation: el índice único (service_id, rater_id,
    // rated_id) ya tiene fila para este par, o sea, ya calificó.
    if (e.code == '23505') {
      return (
        ok: false,
        alreadyRated: true,
        error: 'Ya calificaste este servicio.',
      );
    }
    debugPrint(
      'MUEVEX submitClientRating: code=${e.code} message=${e.message}',
    );
    return (ok: false, alreadyRated: false, error: _ratingErrorMessage(e));
  } catch (e) {
    debugPrint('MUEVEX submitClientRating: $e');
    return (ok: false, alreadyRated: false, error: _ratingErrorMessage(e));
  }
}

/// Verifica si el cliente actual ya calificó un servicio.
///
/// Usa `.limit(1)` en vez de `.maybeSingle()`: si por cualquier razón
/// existen duplicados en la BD (indice unico no creado aun, migracion
/// parcial, etc.), `maybeSingle()` lanza PostgrestException y rompe la UI.
/// Con `.limit(1)` devolvemos `true` si hay al menos una fila.
Future<bool> hasClientRatedService(String serviceId) async {
  final user = supabase.auth.currentUser;
  if (user == null) return false;
  final res = await supabase
      .from('ratings')
      .select('id')
      .eq('service_id', serviceId)
      .eq('rater_id', user.id)
      .limit(1);
  return (res as List).isNotEmpty;
}

// ===========================================================================
// INVOICES / FACTURAS
// ===========================================================================
//
// Toda la escritura va por funciones `SECURITY DEFINER` de Postgres
// (docs/migracion_facturacion_v4.sql), no por INSERT/UPDATE directo.
//
// Por qué: si `invoices` aceptara INSERT con la anon key, cualquiera con esa
// clave podría emitir una factura por el precio que quisiera. Las funciones
// corren con permisos de postgres y validan que quien llama sea el cliente o
// el conductor del servicio. Además, el monto NO lo envía el cliente: lo
// calcula el servidor desde el servicio.
//
// Requiere haber ejecutado migracion_facturacion_v4.sql en Supabase.

/// Lee la fila que devuelve una función RPC.
///
/// PostgREST envuelve en una lista el resultado de una función que declara
/// `SETOF tabla`, pero devuelve el objeto suelto cuando la función declara
/// `RETURNS tabla` (tipo fila). [crear_factura_desde_servicio] y
/// [emitir_factura] devuelven el tipo fila, así que llega un `Map`. Este
/// helper acepta las dos formas para que cambiar el `SETOF` en el SQL no rompa
/// la app con un `type 'List<dynamic>' is not a subtype of type 'Map'`.
Map<String, dynamic>? _filaDeRpc(dynamic res) {
  if (res == null) return null;
  if (res is List) {
    if (res.isEmpty) return null;
    return Map<String, dynamic>.from(res.first as Map);
  }
  if (res is Map) return Map<String, dynamic>.from(res);
  throw Exception('La función de facturación devolvió un tipo inesperado');
}

/// Crea la factura de un servicio completado.
///
/// El número consecutivo, los datos del emisor y los montos los pone la base de
/// datos. La función es idempotente: si el servicio ya tiene factura, devuelve
/// esa en vez de crear otra, así que se puede volver a pulsar sin duplicar.
Future<Invoice> createInvoiceFromService(String serviceId) async {
  final res = await supabase.rpc(
    'crear_factura_desde_servicio',
    params: {'p_service_id': serviceId},
  );

  final fila = _filaDeRpc(res);
  if (fila == null) {
    throw Exception('No se pudo crear la factura');
  }

  return Invoice.fromMap(fila);
}

/// Publica la minifactura: marca la factura como `emitida` para que se pueda
/// ver junto a los pedidos.
///
/// La minifactura no es un archivo: se dibuja en la app con los datos que
/// devuelve la base. Por eso aquí no se sube nada a Storage, y por eso
/// `p_pdf_path` va en null. `pdf_url` se queda a null y no molesta: el visor
/// ya no lo mira.
///
/// El paso de `borrador` a `emitida` es lo que decide si se ve: las listas
/// piden solo las `emitida`, porque una que sigue en borrador no se puede
/// enseñar todavía.
///
/// La función es idempotente: si ya está `emitida` la devuelve tal cual, así
/// que un doble toque no rompe nada.
Future<Invoice?> publicarMinifactura(String invoiceId) async {
  final res = await supabase.rpc(
    'emitir_factura',
    params: {
      'p_invoice_id': invoiceId,
      'p_pdf_path': null,
    },
  );

  final fila = _filaDeRpc(res);
  if (fila == null) return null;
  return Invoice.fromMap(fila);
}

/// Obtiene las facturas del cliente actual.
Future<List<Invoice>> getMyInvoices({
  InvoiceStatus? status,
  int limit = 50,
}) async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final baseQuery = supabase
      .from('invoices')
      .select('*, invoice_items(*)')
      .eq('customer_id', user.id);

  final filteredQuery =
      status != null ? baseQuery.eq('status', status.dbName) : baseQuery;

  final res =
      await filteredQuery.order('fecha_emision', ascending: false).limit(limit);

  return (res as List).map((e) => Invoice.fromMap(e)).toList();
}

/// Obtiene las facturas de los servicios del conductor actual.
Future<List<Invoice>> getDriverInvoices({
  InvoiceStatus? status,
  int limit = 50,
}) async {
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final baseQuery = supabase
      .from('invoices')
      .select('*, invoice_items(*)')
      .eq('driver_id', user.id);

  final filteredQuery =
      status != null ? baseQuery.eq('status', status.dbName) : baseQuery;

  final res =
      await filteredQuery.order('fecha_emision', ascending: false).limit(limit);

  return (res as List).map((e) => Invoice.fromMap(e)).toList();
}

/// Obtiene una factura por ID con sus items.
Future<Invoice?> getInvoiceById(String invoiceId) async {
  final res = await supabase
      .from('invoices')
      .select('*, invoice_items(*)')
      .eq('id', invoiceId)
      .maybeSingle();
  if (res == null) return null;
  return Invoice.fromMap(res);
}

/// Anula una factura.
Future<bool> voidInvoice(String invoiceId, String reason) async {
  try {
    await supabase.rpc(
      'anular_factura',
      params: {
        'p_invoice_id': invoiceId,
        'p_motivo': reason,
      },
    );
    return true;
  } catch (e) {
    return false;
  }
}
