import 'package:flutter/material.dart';

import 'package:muevex/core/themes/muevex_theme.dart';

/// Opción de tipo de carga seleccionable en el flujo de solicitud.
class LoadTypeOption {
  final String label;
  final IconData icon;
  final String value;

  const LoadTypeOption(this.label, this.icon, this.value);
}

/// Tipos de carga disponibles en MUEVEX (compartidos entre el mapa y el
/// formulario de creación).
const List<LoadTypeOption> kLoadTypeOptions = [
  LoadTypeOption('Muebles', Icons.chair_outlined, 'muebles'),
  LoadTypeOption('Cajas', Icons.inventory_2_outlined, 'cajas'),
  LoadTypeOption(
      'Electrodomésticos', Icons.local_laundry_service_outlined, 'electrodomesticos'),
  LoadTypeOption('Carga pequeña', Icons.all_inbox_outlined, 'carga'),
  LoadTypeOption('Otro', Icons.category_outlined, 'otro'),
];

/// Selector de tipo de carga en forma de chips con la identidad MUEVEX.
class LoadTypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const LoadTypeSelector({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final option in kLoadTypeOptions)
          _LoadTypeChip(
            option: option,
            selected: selected == option.value,
            onTap: () => onSelect(option.value),
          ),
      ],
    );
  }
}

class _LoadTypeChip extends StatelessWidget {
  final LoadTypeOption option;
  final bool selected;
  final VoidCallback onTap;

  const _LoadTypeChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? MuevexTheme.primaryColor
              : MuevexTheme.primaryColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? MuevexTheme.primaryColor
                : MuevexTheme.primaryColor.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              option.icon,
              size: 18,
              color: selected ? Colors.white : MuevexTheme.primaryColor,
            ),
            const SizedBox(width: 7),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : const Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }
}