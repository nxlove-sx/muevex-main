import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Campo de búsqueda flotante de lugares.
///
/// Se muestra sobre el mapa con fondo blanco, esquinas redondeadas y sombra
/// suave. Permite escribir la dirección/lugar y notifica cada cambio (el
/// debounce lo gestiona el provider de búsqueda).
class LocationSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool forOrigin;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;
  final VoidCallback onClear;

  const LocationSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBack,
    required this.onClear,
    this.forOrigin = false,
  });

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(LocationSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _hasText = widget.controller.text.isNotEmpty;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MuevexTheme.surfaceOf(context),
      elevation: 0,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
              onPressed: widget.onBack,
            ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                textInputAction: TextInputAction.search,
                onChanged: widget.onChanged,
                autocorrect: false,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: widget.forOrigin
                      ? '¿Dónde se encuentra tu carga?'
                      : '¿A dónde quieres ir?',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _hasText
                  ? IconButton(
                      key: const ValueKey('clear'),
                      tooltip: 'Limpiar',
                      icon: Icon(
                        Icons.close,
                        color: MuevexTheme.secondaryTextOf(context),
                        size: 20,
                      ),
                      onPressed: () {
                        widget.controller.clear();
                        widget.onClear();
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
