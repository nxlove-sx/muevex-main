import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Tarjeta flotante de Origen → Destino.
///
/// Modelo de las apps de transporte: muestra el origen ("Mi ubicación") y el
/// destino ("¿A dónde quieres ir?") y permite tocar cualquiera de los dos
/// campos para abrir el buscador correspondiente.
class OriginDestinationSelector extends StatelessWidget {
  final String? originName;
  final String? destinationName;
  final VoidCallback onTapOrigin;
  final VoidCallback onTapDestination;
  final VoidCallback? onUseMyLocation;
  final bool locating;

  const OriginDestinationSelector({
    super.key,
    required this.originName,
    required this.destinationName,
    required this.onTapOrigin,
    required this.onTapDestination,
    this.onUseMyLocation,
    this.locating = false,
  });

  @override
  Widget build(BuildContext context) {
    final origin = (originName == null || originName!.isEmpty)
        ? 'Mi ubicación'
        : originName!;
    final destination = (destinationName == null || destinationName!.isEmpty)
        ? '¿A dónde quieres ir?'
        : destinationName!;

    return Container(
      decoration: BoxDecoration(
        color: MuevexTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FieldRow(
            icon: Icons.trip_origin,
            iconColor: MuevexTheme.successColor,
            label: 'Origen',
            value: origin,
            onTap: onTapOrigin,
            trailing: onUseMyLocation == null
                ? null
                : _UseMyLocationButton(
                    onTap: onUseMyLocation!,
                    locating: locating,
                  ),
          ),
          const Divider(height: 1, indent: 58),
          _FieldRow(
            icon: Icons.location_on,
            iconColor: MuevexTheme.secondaryColor,
            label: 'Destino',
            value: destination,
            onTap: onTapDestination,
            showSearchIcon: true,
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool showSearchIcon;
  final Widget? trailing;

  const _FieldRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
    this.showSearchIcon = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
            if (trailing != null)
              trailing!
            else if (showSearchIcon)
              Icon(Icons.search, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Botón "Usar mi ubicación" dentro de la fila de origen.
///
/// Toca el flujo completo (permiso, GPS, obtener posición) sin abrir el
/// buscador; muestra un spinner mientras se ubica.
class _UseMyLocationButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool locating;

  const _UseMyLocationButton({required this.onTap, required this.locating});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: locating ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: locating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.my_location,
                      size: 16, color: MuevexTheme.primaryColor),
                  SizedBox(width: 5),
                  Text(
                    'Usar mi ubicación',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: MuevexTheme.primaryColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}