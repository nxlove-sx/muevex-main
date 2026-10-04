import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'package:muevex/core/utils/money.dart';
import 'package:muevex/core/services/location_service.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/widgets/animations.dart';
import 'package:muevex/core/widgets/custom_button.dart';
import 'package:muevex/core/widgets/custom_text_field.dart';
import 'package:muevex/core/widgets/muevex_app_bar.dart';
import 'package:muevex/core/widgets/muevex_snackbar.dart';
import 'package:muevex/core/services/tariff_codec.dart';
import 'package:muevex/core/widgets/price_breakdown_sheet.dart';
import 'package:muevex/core/widgets/articulos_selector_sheet.dart';
import 'package:muevex/core/services/tariff_engine.dart';
import 'package:muevex/features/customer/providers/customer_providers.dart';
import 'package:muevex/features/map/presentation/widgets/map_widget.dart' as mw;
import 'package:muevex/features/service/providers/service_providers.dart';

/// Centro por defecto del mapa: Montería, Córdoba (Colombia).
const LatLng _monteriaCenter = LatLng(8.7566, -75.8900);

/// Selector de origen del ayudante (incluido / cliente / plataforma).
class _HelpOriginSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _HelpOriginSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final opciones = [
      (
        'incluido',
        'Incluido',
        'El conductor carga y descarga',
        Icons.person_outline
      ),
      (
        'cliente',
        'Lo aporta el cliente',
        'Acompañante del cliente ayuda',
        Icons.group_outlined
      ),
      (
        'plataforma',
        'Ayudante MUEVEX',
        '+ \$30.000 por personal extra',
        Icons.add_circle_outline
      ),
    ];

    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: 'Ayudante para carga/descarga',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      items: opciones
          .map((o) => DropdownMenuItem(
                value: o.$1,
                child: Row(
                  children: [
                    Icon(o.$4,
                        size: 20, color: MuevexTheme.secondaryTextOf(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(o.$2,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(o.$3,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: MuevexTheme.secondaryTextOf(context))),
                        ],
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
      onChanged: (v) => v != null ? onChanged(v) : null,
    );
  }
}

/// Helpers para iconos y colores de categoría (usados en chips de artículos seleccionados).
IconData _iconoCategoria(CategoriaArticulo c) {
  switch (c) {
    case CategoriaArticulo.muebleria:
      return Icons.chair_outlined;
    case CategoriaArticulo.electrodomestico:
      return Icons.kitchen_outlined;
    case CategoriaArticulo.electronica:
      return Icons.tv_outlined;
    case CategoriaArticulo.climatizacion:
      return Icons.ac_unit_outlined;
    case CategoriaArticulo.construccion:
      return Icons.construction_outlined;
    case CategoriaArticulo.bulto:
      return Icons.inventory_2_outlined;
    case CategoriaArticulo.caja:
      return Icons.inventory_outlined;
    case CategoriaArticulo.fragil:
      return Icons.broken_image_outlined;
    case CategoriaArticulo.otro:
      return Icons.category_outlined;
  }
}

Color _colorCategoria(CategoriaArticulo c) {
  switch (c) {
    case CategoriaArticulo.muebleria:
      return const Color(0xFF8B5E3C);
    case CategoriaArticulo.electrodomestico:
      return const Color(0xFF3B82F6);
    case CategoriaArticulo.electronica:
      return const Color(0xFF8B5CF6);
    case CategoriaArticulo.climatizacion:
      return const Color(0xFF06B6D4);
    case CategoriaArticulo.construccion:
      return const Color(0xFF64748B);
    case CategoriaArticulo.bulto:
      return const Color(0xFF65A30D);
    case CategoriaArticulo.caja:
      return const Color(0xFFF59E0B);
    case CategoriaArticulo.fragil:
      return const Color(0xFFEF4444);
    case CategoriaArticulo.otro:
      return const Color(0xFF9CA3AF);
  }
}

/// Formulario de creación de servicio con la identidad nueva de MUEVEX.
///
/// Recibe el origen, destino y tipo de carga ya definidos en el mapa y deja
/// completar la descripción, fotos, pisos y ayuda de carga antes de crear la
/// solicitud. Todo con el mismo lenguaje visual de la pantalla de mapa.
class CreateServicePage extends ConsumerStatefulWidget {
  const CreateServicePage({super.key});

  @override
  ConsumerState<CreateServicePage> createState() => _CreateServicePageState();
}

class _CreateServicePageState extends ConsumerState<CreateServicePage> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // Solo usa la ubicación si el permiso ya está concedido; NO muestra el
    // diálogo del sistema aquí para evitar la pantalla en blanco.
    _initLocationTracking();
  }

  /// Usa la ubicación actual SOLO si el permiso ya está concedido.
  /// Auto-llena el origen sin sobrescribir uno ya elegido. No se mantiene un
  /// stream de GPS abierto: pedir la posición al crear/formulario basta.
  Future<void> _initLocationTracking() async {
    final position =
        await LocationService.getCurrentPosition(requestIfNeeded: false);
    final notifier = ref.read(serviceFormProvider.notifier);
    if (!mounted) return;

    if (position != null) {
      if ((ref.read(serviceFormProvider)['originLat'] as num?) == 0) {
        notifier.setOriginLat(position.latitude);
        notifier.setOriginLng(position.longitude);
        notifier.setOriginName('Mi ubicación');
      }
    }
  }

  /// Fija el origen en la ubicación actual. Este botón es el punto donde se
  /// solicita el permiso (contexto claro para el usuario).
  Future<void> _pickCurrentLocationAsOrigin() async {
    setState(() => _locating = true);
    final position =
        await LocationService.getCurrentPosition(requestIfNeeded: true);
    if (!mounted) return;
    setState(() => _locating = false);

    final notifier = ref.read(serviceFormProvider.notifier);
    if (position != null) {
      notifier.setOriginLat(position.latitude);
      notifier.setOriginLng(position.longitude);
      notifier.setOriginName('Mi ubicación');
      showMuevexSnackBar(
        context,
        message: 'Origen fijado en tu ubicación actual',
        icon: Icons.my_location,
      );
    } else {
      showMuevexSnackBar(
        context,
        message: 'No se pudo obtener tu ubicación. Revisa que el GPS esté '
            'activado y aceptes el permiso.',
        icon: Icons.gps_off,
        isError: true,
      );
    }
  }

  Future<void> _pickPhotos() async {
    final files = await _imagePicker.pickMultiImage();
    final notifier = ref.read(serviceFormProvider.notifier);
    if (files.isNotEmpty && mounted) {
      for (final file in files) {
        notifier.addPhoto(file.path);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(serviceFormProvider);
    final recommendedPrice = ref.watch(recommendedPriceProvider);
    final notifier = ref.read(serviceFormProvider.notifier);

    // Coordenadas y nombres actuales del formulario
    final originLat = (formState['originLat'] as num?)?.toDouble() ?? 0.0;
    final originLng = (formState['originLng'] as num?)?.toDouble() ?? 0.0;
    final destLat = (formState['destinationLat'] as num?)?.toDouble() ?? 0.0;
    final destLng = (formState['destinationLng'] as num?)?.toDouble() ?? 0.0;
    final hasOrigin = originLat != 0 && originLng != 0;
    final hasDestination = destLat != 0 && destLng != 0;
    final photos = List<String>.from(formState['photos'] as List? ?? []);
    final loadType = formState['loadType'] as String? ?? 'muebles';
    final originName = (formState['originName'] as String? ?? '').trim().isEmpty
        ? 'Sin definir'
        : formState['originName'] as String;
    final destinationName =
        (formState['destinationName'] as String? ?? '').trim().isEmpty
            ? 'Sin definir'
            : formState['destinationName'] as String;

    debugPrint('MUEVEX create-page open loadType=$loadType '
        'origin="$originName" dest="$destinationName" '
        'hasOrigin=$hasOrigin hasDestination=$hasDestination');

    final routeComplete = hasOrigin && hasDestination;

    return Scaffold(
      appBar: MuevexGradientAppBar(title: 'Detalles de la solicitud'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------------------
            // Ruta del servicio
            // ------------------------------------------------------------
            _SectionCard(
              title: 'Ruta del servicio',
              subtitle: 'Origen y destino definidos en el mapa',
              child: Column(
                children: [
                  _RouteRow(
                    icon: Icons.trip_origin,
                    iconColor: MuevexTheme.successColor,
                    label: 'Origen',
                    value: originName,
                    onTap: () => _pickPoint(context, ref, isOrigin: true),
                  ),
                  const Divider(height: 1, indent: 48),
                  _RouteRow(
                    icon: Icons.location_on,
                    iconColor: MuevexTheme.secondaryColor,
                    label: 'Destino',
                    value: destinationName,
                    onTap: () => _pickPoint(context, ref, isOrigin: false),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MuevexTheme.primaryColor,
                            side: BorderSide(
                              color: MuevexTheme.primaryColor
                                  .withValues(alpha: 0.5),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _locating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location, size: 18),
                          label: const Text('Mi ubicación'),
                          onPressed: _pickCurrentLocationAsOrigin,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MuevexTheme.primaryColor,
                            side: BorderSide(
                              color: MuevexTheme.primaryColor
                                  .withValues(alpha: 0.5),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon:
                              const Icon(Icons.photo_camera_outlined, size: 18),
                          label: Text(
                              photos.isEmpty ? 'Tomar fotos' : 'Añadir fotos'),
                          onPressed: _pickPhotos,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!routeComplete) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: MuevexTheme.warningColor,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Define el origen y el destino para poder crear tu '
                      'solicitud.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // ------------------------------------------------------------
            // Descripción
            // ------------------------------------------------------------
            _SectionCard(
              title: '¿Qué necesitas mover?',
              subtitle: 'Detalles de la carga y fotos opcionales',
              child: Column(
                children: [
                  CustomTextField(
                    label: 'Describe la carga',
                    initialValue: formState['description'],
                    maxLines: 3,
                    onChanged: (v) => notifier.setDescription(v ?? ''),
                  ),
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Fotos de la carga',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MuevexTheme.secondaryTextOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PhotoGrid(
                      photos: photos,
                      onRemove: (path) => notifier.removePhoto(path),
                      onAdd: _pickPhotos,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ------------------------------------------------------------
            // Artículos del servicio (selector visual)
            // ------------------------------------------------------------
            _SectionCard(
              title: 'Artículos del servicio',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final formState = ref.watch(serviceFormProvider);
                      final items = (formState['items'] as List?)
                              ?.cast<Map<String, dynamic>>() ??
                          const [];
                      final seleccionados = items.fold<int>(
                          0,
                          (a, e) =>
                              a + ((e['cantidad'] as num?)?.toInt() ?? 0));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (seleccionados > 0) ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: items.map((e) {
                                final art = TarifaEngine.articuloPorId(
                                    e['id'] as String? ?? '');
                                final cant =
                                    (e['cantidad'] as num?)?.toInt() ?? 0;
                                if (art == null) return const SizedBox.shrink();
                                return InputChip(
                                  label: Text('${art.nombre} ×$cant'),
                                  avatar: Icon(_iconoCategoria(art.categoria),
                                      size: 16,
                                      color: _colorCategoria(art.categoria)),
                                  onDeleted: () =>
                                      notifier.restarArticulo(art.id),
                                  deleteIconColor: MuevexTheme.errorColor,
                                  labelStyle: const TextStyle(fontSize: 13),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final actuales = (formState['items'] as List?)
                                        ?.cast<Map<String, dynamic>>() ??
                                    const [];
                                final seleccion =
                                    await showArticulosSelectorSheet(
                                  context,
                                  articulosActuales:
                                      articulosDesdeJson(actuales),
                                );
                                if (seleccion != null && context.mounted) {
                                  notifier.setItems(seleccion);
                                }
                              },
                              icon:
                                  const Icon(Icons.add_shopping_cart_outlined),
                              label: Text(seleccionados > 0
                                  ? 'Modificar artículos ($seleccionados)'
                                  : 'Elegir artículos'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                side:
                                    BorderSide(color: MuevexTheme.primaryColor),
                                foregroundColor: MuevexTheme.primaryColor,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ------------------------------------------------------------
            // Pisos, viajes y ayudante
            // ------------------------------------------------------------
            _SectionCard(
              title: 'Detalles del servicio',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          label: 'Pisos en recogida',
                          initialValue: formState['floorsPickup'].toString(),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => notifier
                              .setFloorsPickup(int.tryParse(v ?? '') ?? 0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomTextField(
                          label: 'Pisos en entrega',
                          initialValue: formState['floorsDelivery'].toString(),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => notifier
                              .setFloorsDelivery(int.tryParse(v ?? '') ?? 0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          label: 'Número de viajes',
                          initialValue: formState['trips'].toString(),
                          keyboardType: TextInputType.number,
                          onChanged: (v) =>
                              notifier.setTrips(int.tryParse(v ?? '') ?? 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _HelpOriginSelector(
                          value: formState['helperOrigin'] as String? ??
                              'incluido',
                          onChanged: (v) => notifier.setHelperOrigin(
                              OrigenAyudante.values.firstWhere(
                                  (e) => e.name == v,
                                  orElse: () => OrigenAyudante.incluido)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ------------------------------------------------------------
            // Precio estimado
            // ------------------------------------------------------------
            _SectionCard(
              child: GestureDetector(
                // Se pasa la tarifa ya calculada, la misma que pinta el precio de
                // arriba. Si se reconstruyera la entrada aquí, el desglose
                // podría no coincidir con el precio.
                onTap: () => showPriceBreakdownSheet(
                  context,
                  tarifa: ref.watch(tarifaActualProvider),
                ),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Precio estimado',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Incluye distancia y tipo de carga',
                            style: TextStyle(
                                fontSize: 12.5, color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // El número grande es lo que se va a pagar DE VERDAD,
                        // con el IVA encima, para que sea el mismo que sale
                        // como "Total a pagar" en el desglose. Antes aquí se
                        // pintaba el neto y el desglose enseñaba otro 19% más,
                        // y parecía que eran dos precios distintos sin relación.
                        AnimatedNumber(
                          value: precioTotalConIva(recommendedPrice),
                          formatter: (v) => money(v),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: MuevexTheme.secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Neto ${money(recommendedPrice)} + IVA '
                          '${money(recommendedPrice * ivaRate)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                              size: 13,
                              color: MuevexTheme.primaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Ver desglose',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: MuevexTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ------------------------------------------------------------
            // Crear solicitud
            // ------------------------------------------------------------
            CustomButton(
              text: 'Crear Solicitud',
              icon: Icons.arrow_forward,
              backgroundColor: MuevexTheme.secondaryColor,
              textColor: Colors.white,
              borderRadius: BorderRadius.circular(16),
              enabled: routeComplete,
              onPressed: () async {
                if (!hasOrigin) {
                  showMuevexSnackBar(
                    context,
                    message: 'Selecciona el punto de origen',
                    icon: Icons.trip_origin,
                    isError: true,
                  );
                  return;
                }
                if (!hasDestination) {
                  showMuevexSnackBar(
                    context,
                    message: 'Selecciona el punto de destino',
                    icon: Icons.location_on,
                    isError: true,
                  );
                  return;
                }

                final data = {
                  'originLat': formState['originLat'],
                  'originLng': formState['originLng'],
                  'destinationLat': formState['destinationLat'],
                  'destinationLng': formState['destinationLng'],
                  'originName': formState['originName'],
                  'destinationName': formState['destinationName'],
                  'description': formState['description'],
                  'loadType': formState['loadType'],
                  'needsHelp': formState['needsHelp'],
                  'floors': formState['floors'],
                  'loadWeight': formState['loadWeight'] ?? 0,
                  'photos': photos,
                  'priceBase': recommendedPrice,
                  'priceTotal': recommendedPrice,
                  'priceRecommended': recommendedPrice,
                };

                String errorMsg = 'No se pudo crear el servicio';
                var success = false;
                try {
                  success = await ref.read(createServiceProvider(data).future);
                } catch (e) {
                  errorMsg =
                      'No se pudo crear el servicio. Inténtalo de nuevo.';
                  debugPrint('MUEVEX crear click error: $e');
                }
                if (success && context.mounted) {
                  notifier.clear();
                  ref.invalidate(customerServicesProvider);
                  showMuevexSnackBar(
                    context,
                    message: 'Servicio creado correctamente',
                    icon: Icons.check_circle,
                  );
                  context.go('/');
                } else if (context.mounted) {
                  showMuevexSnackBar(
                    context,
                    message: errorMsg,
                    icon: Icons.error_outline,
                    isError: true,
                  );
                }
              },
            ),
            if (!routeComplete) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Completa la ruta para habilitar la solicitud',
                  style: TextStyle(
                    fontSize: 13,
                    color: MuevexTheme.secondaryTextOf(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Abre un selector de punto a pantalla completa usando el mapa.
  Future<void> _pickPoint(BuildContext context, WidgetRef ref,
      {required bool isOrigin}) async {
    final notifier = ref.read(serviceFormProvider.notifier);
    final formState = ref.read(serviceFormProvider);

    // Punto actual (para centrar el mapa)
    LatLng currentPoint;
    if (isOrigin) {
      final lat = (formState['originLat'] as num?)?.toDouble() ?? 8.7566;
      final lng = (formState['originLng'] as num?)?.toDouble() ?? -75.8900;
      currentPoint = lat == 0 && lng == 0 ? _monteriaCenter : LatLng(lat, lng);
    } else {
      final lat = (formState['destinationLat'] as num?)?.toDouble() ?? 8.7566;
      final lng = (formState['destinationLng'] as num?)?.toDouble() ?? -75.8900;
      currentPoint = lat == 0 && lng == 0 ? _monteriaCenter : LatLng(lat, lng);
    }

    LatLng? selected = currentPoint;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (dialogContext, setState) {
            return Scaffold(
              backgroundColor: Colors.white,
              appBar: MuevexGradientAppBar(
                title: isOrigin ? 'Elegir Origen' : 'Elegir Destino',
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      // Confirmar selección
                      if (isOrigin) {
                        notifier.setOriginLat(selected!.latitude);
                        notifier.setOriginLng(selected!.longitude);
                        notifier.setOriginName('Punto en el mapa');
                      } else {
                        notifier.setDestinationLat(selected!.latitude);
                        notifier.setDestinationLng(selected!.longitude);
                        notifier.setDestinationName('Punto en el mapa');
                      }
                    },
                    child: const Text(
                      'Confirmar',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              body: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: currentPoint,
                      initialZoom: 14,
                      minZoom: 3,
                      maxZoom: mw.kMapMaxZoom,
                      backgroundColor: mw.kMapBackgroundColor,
                      onTap: (tapPosition, point) {
                        setState(() => selected = point);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: mw.kEsriDarkBaseTileUrl,
                        userAgentPackageName: 'com.example.muevex',
                      ),
                      TileLayer(
                        urlTemplate: mw.kEsriDarkReferenceTileUrl,
                        userAgentPackageName: 'com.example.muevex',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: selected ?? currentPoint,
                            width: 40,
                            height: 40,
                            child: Center(
                              child: Icon(
                                isOrigin
                                    ? Icons.trip_origin
                                    : Icons.location_on,
                                color: isOrigin
                                    ? MuevexTheme.successColor
                                    : MuevexTheme.secondaryColor,
                                size: 32,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Positioned(
                    left: 10,
                    bottom: 10,
                    child: Text(
                      '© OpenStreetMap contributors · Esri',
                      style: TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                  ),
                  // Indicador central
                  const IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.my_location,
                              color: MuevexTheme.primaryColor, size: 28),
                          SizedBox(height: 4),
                          Text(
                            'Toca el mapa para mover el marcador',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                backgroundColor: Colors.black38),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Tarjeta de sección con el lenguaje visual nuevo de MUEVEX.
class _SectionCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MuevexTheme.surfaceBorderOf(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1F2937),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style:
                    const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
              ),
            ],
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// Fila de Origen/Destino dentro de la tarjeta de ruta.
class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 22),
          ],
        ),
      ),
    );
  }
}

/// Control de "requiere ayuda para cargar" con la identidad de la app.

/// Cuadrícula de miniaturas de fotos de la carga con opción de eliminar
/// y añadir más.
class _PhotoGrid extends StatelessWidget {
  final List<String> photos;
  final void Function(String path) onRemove;
  final VoidCallback onAdd;

  const _PhotoGrid({
    required this.photos,
    required this.onRemove,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final path in photos)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Image.file(
                  File(path),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => onRemove(path),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        InkWell(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: MuevexTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: MuevexTheme.primaryColor.withValues(alpha: 0.4)),
            ),
            child:
                const Icon(Icons.add_a_photo, color: MuevexTheme.primaryColor),
          ),
        ),
      ],
    );
  }
}
