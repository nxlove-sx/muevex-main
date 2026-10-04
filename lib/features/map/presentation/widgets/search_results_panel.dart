import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/features/map/models/location_result.dart';
import 'package:muevex/features/map/providers/map_search_provider.dart';

/// Lista de resultados del buscador de lugares (item 6).
///
/// Muestra los distintos estados:
///  - `searching`: indicador de carga.
///  - `results`: lista de lugares reales.
///  - `noResults`: mensaje "No se encontraron lugares".
///  - `error`: mensaje y botón para reintentar.
class SearchResultsPanel extends StatelessWidget {
  final MapSearchState state;
  final ValueChanged<LocationResult> onSelect;
  final VoidCallback onRetry;
  final double maxHeight;

  const SearchResultsPanel({
    super.key,
    required this.state,
    required this.onSelect,
    required this.onRetry,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = switch (state.status) {
      MapSearchStatus.searching => const _CenteredMessage(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      MapSearchStatus.noResults => const _CenteredMessage(
          icon: Icons.search_off,
          text: 'No se encontraron lugares.',
        ),
      MapSearchStatus.error => _CenteredMessage(
          icon: Icons.error_outline,
          text: state.error ?? 'Error al buscar. Intenta nuevamente.',
          action: TextButton(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ),
      MapSearchStatus.idle ||
      MapSearchStatus.locationSelected =>
        const _CenteredMessage(
          icon: Icons.edit_location_alt_outlined,
          text: 'Escribe al menos 3 caracteres para buscar',
        ),
      MapSearchStatus.results => ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: state.results.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 62),
          itemBuilder: (context, index) {
            final result = state.results[index];
            return _ResultTile(
              result: result,
              index: index,
              onTap: () => onSelect(result),
            );
          },
        ),
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        margin: const EdgeInsets.only(top: 8),
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
        child: content,
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final LocationResult result;
  final int index;
  final VoidCallback onTap;

  const _ResultTile({
    required this.result,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: MuevexTheme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.place_outlined,
                color: MuevexTheme.primaryColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: MuevexTheme.secondaryTextOf(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.north_west, color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData? icon;
  final String? text;
  final Widget? child;
  final Widget? action;

  const _CenteredMessage({this.icon, this.text, this.child, this.action});

  @override
  Widget build(BuildContext context) {
    final IconData? icon = this.icon;
    final String? text = this.text;
    final Widget? centerChild = child;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (centerChild != null) centerChild,
          if (icon != null) ...[
            Icon(icon, size: 34, color: Colors.grey.shade400),
            const SizedBox(height: 10),
          ],
          if (text != null)
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5, color: MuevexTheme.secondaryTextOf(context)),
            ),
          if (action != null) ...[
            const SizedBox(height: 4),
            action!,
          ],
        ],
      ),
    );
  }
}
