import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:muevex/core/models/customer_profile_model.dart';
import 'package:muevex/core/models/invoice_model.dart';
import 'package:muevex/core/models/service_model.dart';
import 'package:muevex/core/models/user_model.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/features/auth/providers/auth_provider.dart';
import 'package:muevex/features/customer/presentation/pages/customer_home_page.dart';
import 'package:muevex/features/customer/providers/customer_providers.dart';
import 'package:muevex/features/notifications/presentation/pages/notifications_page.dart';

/// Pantallas reales de gamas distintas, no una sola.
///
/// Un diseño comprobado únicamente en un móvil de 6" se rompe en cuanto entra un
/// botón más o un móvil pequeño, así que la matriz es parte del test y no un
/// detalle.
const _pantallas = <String, Size>{
  'pantalla pequeña 360x640': Size(360, 640),
  'móvil normal 412x915': Size(412, 915),
  'tablet 800x1100': Size(800, 1100),
};

/// `AuthNotifier` real se suscribe a `supabase.auth`, que en un test no existe.
/// Se subclasses para dejar solo el estado que importa.
class _FakeAuth extends AuthNotifier {
  _FakeAuth() : super() {
    state = AsyncValue.data(_usuario);
  }
}

final _usuario = User(
  id: '37a6d4f8-ff27-4269-bce9-fb42d223590a',
  email: 'prueba.facturacion@muevex.test',
  role: UserRole.customer,
  name: 'Prueba Facturación',
  createdAt: DateTime(2026, 1, 1),
);

Service _servicio({
  required String id,
  required ServiceStatus status,
  String? driverId,
  String? originName,
  String? destinationName,
  String description = '',
  double price = 0,
  double weightKg = 0,
}) {
  return Service(
    id: id,
    customerId: _usuario.id,
    driverId: driverId,
    status: status,
    priceBase: price,
    estimatedPrice: price,
    originLat: 6.2442,
    originLng: -75.5812,
    destinationLat: 6.2500,
    destinationLng: -75.5700,
    originName: originName,
    destinationName: destinationName,
    description: description,
    loadWeightKg: weightKg,
    photos: const ['a', 'b'],
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  );
}

/// Monta el home con la lista dada y devuelve los errores de layout que Flutter
/// haya reportado. Solo se guardan los de desbordamiento: son los que hacen que
/// "se vea profesional" y no se vea roto.
Future<List<String>> _pumpHome(
  WidgetTester tester,
  List<Service> servicios, {
  Size tamano = const Size(412, 915),
  double escalaTexto = 1.0,
  Brightness brillo = Brightness.light,
  void Function()? verificar,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final flutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    final texto = details.exceptionAsString();
    if (texto.contains('overflowed')) errores.add(texto);
    flutterError?.call(details);
  };
  addTearDown(() => FlutterError.onError = flutterError);

  final tema =
      brillo == Brightness.dark ? MuevexTheme.dark() : MuevexTheme.light();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuth()),
        customerServicesProvider.overrideWith((ref) async => servicios),
        customerProfileProvider.overrideWith(
          (ref) async => CustomerProfile(
            id: 'p1',
            userId: _usuario.id,
            totalServices: servicios.length,
          ),
        ),
        myInvoicesByServiceProvider
            .overrideWith((ref) async => <String, Invoice>{}),
        unreadNotificationsCountProvider.overrideWithValue(0),
      ],
      child: MaterialApp(
        theme: tema,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(escalaTexto)),
          child: child!,
        ),
        home: const CustomerHomePage(),
      ),
    ),
  );
  await tester.pump();

  // Las animaciones de entrada son escalonadas: con 7 tarjetas el último
  // retardo es ~500 ms y la animación 450 ms más. Un solo salto de 2 s las
  // deja todas resueltas.
  await tester.pump(const Duration(seconds: 2));

  // Las aserciones se lanzan aquí y no después: una vez desmontado el árbol los
  // finders ya no encuentran nada.
  try {
    verificar?.call();
  } finally {
    // Montar un árbol vacío desmonta la home y cancela sus temporizadores
    // periódicos (el contador de "hace X min"). Sin esto el test falla al final
    // con "A Timer is still pending", que no es un fallo de la app.
    await tester.pumpWidget(const SizedBox.shrink());
  }

  return errores;
}

/// Una tarjeta por cada estado en el que se puede encontrar un servicio.
final _todosLosEstados = <Service>[
  _servicio(
    id: 'solicitado',
    status: ServiceStatus.solicitado,
    originName: 'Carrera 43A # 1-50, Medellín',
    description: 'Mudanza de un apartamento',
    price: 84500,
    weightKg: 320,
  ),
  _servicio(
    id: 'aceptado',
    status: ServiceStatus.aceptado,
    driverId: 'd-1',
    originName: 'Calle 10 # 30-20, Medellín',
    destinationName: 'Carrera 70 # 1-50, Medellín',
    price: 84500,
  ),
  _servicio(
    id: 'en-recogida',
    status: ServiceStatus.enRecogida,
    driverId: 'd-2',
    originName: 'Calle 10 # 30-20, Medellín',
    destinationName: 'Carrera 70 # 1-50, Medellín',
    price: 120000,
    weightKg: 540,
  ),
  _servicio(
    id: 'en-curso',
    status: ServiceStatus.enCurso,
    driverId: 'd-3',
    originName: 'Calle 10 # 30-20, Medellín',
    destinationName: 'Carrera 70 # 1-50, Medellín',
    price: 120000,
  ),
  _servicio(
    id: 'completado',
    status: ServiceStatus.completado,
    driverId: 'd-4',
    originName: 'Avenida Regional # 100-50, Medellín',
    destinationName: 'Centro Comercial El Tesoro, Local 204, Medellín',
    price: 210000,
    weightKg: 780,
  ),
  _servicio(
    id: 'cancelado',
    status: ServiceStatus.canceladoCliente,
    originName: 'Calle 10 # 30-20, Medellín',
    price: 84500,
  ),
];

void main() {
  testWidgets('un servicio completado se ve en el home', (tester) async {
    await _pumpHome(
      tester,
      [
        _servicio(
          id: 'a',
          status: ServiceStatus.completado,
          driverId: 'driver-1',
          originName: 'Calle 10 # 30-20, Medellín',
          destinationName: 'Carrera 70 # 1-50, Medellín',
        ),
      ],
      verificar: () {
        // Antes, la home solo listaba servicios activos: al completarse uno su
        // tarjeta desaparecía y "Calificar" se quedaba sin dónde pulsarse. El
        // sistema de calificaciones parecía roto sin estar roto.
        expect(find.text('FINALIZADOS'), findsOneWidget);
        expect(find.text('Calle 10 # 30-20, Medellín'), findsOneWidget);
        expect(find.text('Carrera 70 # 1-50, Medellín'), findsOneWidget);
        // Y el botón de calificar tiene que estar ahí, no solo el texto.
        expect(find.text('Calificar'), findsOneWidget);
      },
    );
  });

  testWidgets('un servicio activo se ve en su propia sección', (tester) async {
    await _pumpHome(tester, _todosLosEstados, verificar: () {
      expect(find.text('EN CURSO'), findsOneWidget);
      expect(find.text('FINALIZADOS'), findsOneWidget);
      // Solo los servicios en curso muestran la barra de fases: hay cuatro
      // activos y uno terminado, así que cuatro barras y ningún "Solicitado"
      // resaltado en la del completado.
      expect(find.text('Recogida'), findsNWidgets(4));
      // Un solo botón de calificar: hay un único servicio completado.
      expect(find.text('Calificar'), findsOneWidget);
    });
  });

  testWidgets('el botón Calificar queda a la vista sin desplazarse',
      (tester) async {
    await _pumpHome(tester, [
      _servicio(
        id: 'a',
        status: ServiceStatus.completado,
        driverId: 'driver-1',
        originName: 'Calle 10 # 30-20, Medellín',
        destinationName: 'Carrera 70 # 1-50, Medellín',
      ),
    ], verificar: () {
      // Un botón que existe pero queda debajo del pliegue es un botón que el
      // usuario no encuentra: mide que cabe entero en la pantalla sin hacer
      // scroll.
      final boton = tester.getRect(find.text('Calificar'));
      final pantalla = tester.view.physicalSize;
      expect(boton.top, greaterThanOrEqualTo(0),
          reason: 'el botón quedó fuera por arriba');
      expect(boton.bottom, lessThanOrEqualTo(pantalla.height),
          reason: 'el botón quedó fuera por abajo: hay que hacer scroll');
      expect(boton.width, greaterThan(40));
    });
  });

  testWidgets('sin desbordes con todos los estados a la vez', (tester) async {
    final errores = await _pumpHome(tester, _todosLosEstados);
    expect(errores, isEmpty, reason: errores.join('\n'));
  });

  for (final pantalla in _pantallas.entries) {
    testWidgets('sin desbordes en ${pantalla.key}', (tester) async {
      final errores =
          await _pumpHome(tester, _todosLosEstados, tamano: pantalla.value);
      expect(errores, isEmpty, reason: errores.join('\n'));
    });
  }

  testWidgets('sin desbordes con la fuente al 160%', (tester) async {
    final errores = await _pumpHome(
      tester,
      _todosLosEstados,
      tamano: const Size(360, 640),
      escalaTexto: 1.6,
    );
    expect(errores, isEmpty, reason: errores.join('\n'));
  });

  testWidgets('sin desbordes en modo oscuro', (tester) async {
    final errores = await _pumpHome(
      tester,
      _todosLosEstados,
      tamano: const Size(360, 640),
      brillo: Brightness.dark,
    );
    expect(errores, isEmpty, reason: errores.join('\n'));
  });

  testWidgets('sin desbordes con un historial largo', (tester) async {
    // El historial se corta a 5, pero con textos largos (direcciones completas,
    // precio de 7 cifras) los botones de calificar y minifactura se acumulan.
    final largos = <Service>[
      for (var i = 0; i < 8; i++)
        _servicio(
          id: 'hist-$i',
          status: ServiceStatus.completado,
          driverId: 'driver-con-nombre-largo-$i',
          originName:
              'Carrera 43A # 1 Sur-50, Edificio Torre breakdowns, Medellín',
          destinationName:
              'Centro Comercial El Tesoro, Local 2045, Medellín, Antioquia',
          description: 'Mudanza de apartamento con ascensor y terraza',
          price: 1234567,
          weightKg: 987,
        ),
    ];
    final errores = await _pumpHome(tester, largos);
    expect(errores, isEmpty, reason: errores.join('\n'));
  });
}
