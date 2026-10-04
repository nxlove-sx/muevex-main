import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones locales de MUEVEX, siempre **con sonido**.
///
/// Usa un canal de Android de importancia alta (`muevex_alertas`) para que el
/// sonido suene también en Android 8+ aunque la app esté en segundo plano.
class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  static const String _channelId = 'muevex_alertas';
  static const String _channelName = 'Alertas MUEVEX';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Prepara el plugin y pide el permiso `POST_NOTIFICATIONS` (Android 13+).
  ///
  /// Se llama una vez desde `main()` antes de `runApp`.
  Future<void> initialize() async {
    if (_initialized) return;

    // Icono propio en vector blanco (`drawable/ic_stat_muevex.xml`).
    //
    // No se puede usar `@mipmap/ic_launcher`: Android renderiza los iconos de
    // la barra de estado como silueta monocroma, y un PNG a color se convierte
    // en un bloque blanco ilegible. El vector pesa 1,9 KB y es nitido en
    // cualquier densidad.
    const androidInit =
        AndroidInitializationSettings('@drawable/ic_stat_muevex');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings:
          const InitializationSettings(android: androidInit, iOS: darwinInit),
    );

    await _createAndroidChannel();
    await requestPermission();

    _initialized = true;
  }

  /// Crea el canal de Android con sonido. Obligatorio en Android 8+ para que
  /// la configuración de sonido del canal se respete.
  Future<void> _createAndroidChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Avisos de pedidos, aceptaciones y estados del servicio.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// Pide los permisos de notificación. En Android < 13 no hay diálogo: se
  /// ignora silenciosamente.
  ///
  /// [force] vuelve a mostrar el diálogo aunque el permiso ya se haya
  /// concedido o denegado antes. Es lo que hay que usar desde Ajustes: en
  /// Android 13+ el sistema deja de mostrar el diálogo tras dos denegaciones,
  /// así que sin este `force` el usuario se quedaría **para siempre** sin
  /// sonido y sin forma de recuperarlo desde la app.
  ///
  /// Devuelve `true` si, tras el intento, las notificaciones están habilitadas.
  Future<bool> requestPermission({bool force = false}) async {
    var granted = await areNotificationsEnabled();

    if (!granted) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // `requestNotificationsPermission` devuelve null en Android < 13, donde
      // no hace falta permiso: se trata como concedido.
      final result = await android?.requestNotificationsPermission();
      granted = result ?? true;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final iosOk = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      _lastIosResult = iosOk ?? false;
      granted = granted && _lastIosResult!;
    }

    if (!granted) {
      debugPrint(
        'MUEVEX: las notificaciones siguen deshabilitadas. En Android 13+ '
        'hay que activarlas en Ajustes → Apps → Notificaciones.',
      );
    }
    return granted;
  }

  /// Último resultado de `requestPermissions` en iOS.
  ///
  /// El plugin de iOS **no** expone `areNotificationsEnabled()` (el de Android
  /// sí), así que no hay forma de consultarlo: el único dato disponible es lo
  /// que devolvió la última petición. `null` significa "todavía no se ha
  /// preguntado", que se trata como concedido para no bloquear la app.
  bool? _lastIosResult;

  /// ¿Están habilitadas las notificaciones a nivel de sistema?
  ///
  /// Distingue "el usuario lo denegó" de "el usuario nunca ha visto el
  /// diálogo", que es la diferencia entre poder reintentar o tener que
  /// mandarlo a Ajustes.
  Future<bool> areNotificationsEnabled() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // null en Android < 13, donde no hace falta permiso.
      return await android.areNotificationsEnabled() ?? true;
    }
    return _lastIosResult ?? true;
  }

  /// Muestra una notificación local con sonido.
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Avisos de MUEVEX',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.event,
      playSound: true,
      enableVibration: true,
      showWhen: true,
      visibility: NotificationVisibility.public,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
          android: androidDetails, iOS: darwinDetails),
      payload: payload,
    );
  }

  /// Muestra la notificación de un evento de servicio.
  ///
  /// Si la fila de la BD trae `title`/`message` ([title]/[body]) se usan tal
  /// cual; si no, se generan a partir de [type].
  Future<void> showOrderEventNotification({
    required String type,
    required String userRole,
    required Map<String, dynamic> data,
    String? title,
    String? body,
  }) async {
    if (!_initialized) await initialize();

    final isCustomer = userRole == 'customer';
    final (fallbackTitle, fallbackBody) = _describe(type, data, isCustomer);

    await showNotification(
      title: (title != null && title.trim().isNotEmpty) ? title : fallbackTitle,
      body: (body != null && body.trim().isNotEmpty) ? body : fallbackBody,
      payload: type,
    );
  }

  /// Descripciones por defecto según el tipo de evento.
  static (String, String) _describe(
    String type,
    Map<String, dynamic> data,
    bool isCustomer,
  ) {
    final ruta = [
      if (data['originName'] != null) data['originName'],
      if (data['destinationName'] != null) data['destinationName'],
    ].join(' → ');

    switch (type) {
      // --- Eventos que ve el CONDUCTOR ---
      case 'new_order':
      case 'nuevo_pedido':
        return (
          'Nueva solicitud de servicio',
          isCustomer
              ? (ruta.isEmpty ? 'Tu servicio fue solicitado.' : ruta)
              : (ruta.isEmpty
                  ? 'Hay un nuevo servicio disponible.'
                  : 'Recoger en $ruta'),
        );
      // `service_accepted`, `service_arrival` y `service_cancelled_by_driver`
      // son los valores que escribe la BD de verdad (ver
      // `docs/migracion_integracion.sql`, ALTER TYPE del enum). Los nombres
      // "bonitos" de abajo se conservan por si algún flujo antiguo los usa, pero
      // los reales tienen que estar aquí o caían en `default` y el push se
      //titulaba solo "MUEVEX".
      case 'order_accepted':
      case 'pedido_aceptado':
      case 'service_accepted':
        return (
          isCustomer ? 'Conductor asignado' : 'Solicitud aceptada',
          isCustomer
              ? 'Un conductor aceptó tu servicio.'
              : 'Aceptaste el servicio. Dirígete al punto de recogida.',
        );
      case 'driver_assigned':
        return ('Conductor asignado', 'Ya hay un conductor para tu servicio.');
      case 'driver_arriving':
      case 'service_arrival':
        return (
          isCustomer ? 'Conductor llegando' : 'Servicio en recogida',
          isCustomer
              ? 'El conductor está cerca de tu ubicación.'
              : 'El cliente está listo para la recogida.',
        );

      // --- Eventos que ve el CLIENTE ---
      case 'service_started':
      case 'en_curso':
        return ('Servicio en curso', 'El conductor va hacia tu destino.');
      case 'service_completed':
      case 'completado':
        return (
          'Servicio completado',
          isCustomer
              ? 'Tu servicio terminó. ¡Gracias por usar MUEVEX!'
              : 'Servicio finalizado correctamente.',
        );
      case 'service_cancelled':
      case 'service_cancelled_by_driver':
      case 'cancelado':
        return (
          isCustomer ? 'Servicio cancelado' : 'Has cancelado el servicio',
          isCustomer
              ? 'El servicio fue cancelado.'
              : 'Has cancelado el servicio. El cliente ha sido avisado.',
        );

      // --- Otros ---
      case 'new_rating':
        return (
          'Nueva calificación',
          'Recibiste una calificación por tu servicio.'
        );
      case 'payment_received':
        return (
          'Pago recibido',
          'Se procesó un pago${data['amount'] != null ? ' de ${data['amount']}' : ''}.',
        );
      default:
        debugPrint('MUEVEX: tipo de notificación no contemplado: "$type"');
        return (
          'MUEVEX',
          data['message']?.toString() ?? 'Tienes una nueva notificación.',
        );
    }
  }

  int _nextId = 1;
}

/// Instancia global del servicio de notificaciones.
final NotificationService notificationService = NotificationService();
