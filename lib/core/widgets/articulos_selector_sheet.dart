/// Selector visual de artículos para el formulario de servicio.
///
/// Muestra el catálogo de `TarifaEngine` agrupado por categoría,
/// con búsqueda, chips de categoría y contador de cantidad por artículo.
/// Devuelve la lista de `ArticuloSeleccionado` elegida.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muevex/core/services/tariff_engine.dart';
import 'package:muevex/core/themes/muevex_theme.dart';
import 'package:muevex/core/utils/money.dart';

/// Abre el selector de artículos.
///
/// [articulosActuales] = selección actual (para pre-seleccionar).
/// Devuelve la nueva lista o `null` si se cancela.
Future<List<ArticuloSeleccionado>?> showArticulosSelectorSheet(
  BuildContext context, {
  required List<ArticuloSeleccionado> articulosActuales,
}) async {
  return await showModalBottomSheet<List<ArticuloSeleccionado>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ArticulosSelectorSheet(
      articulosIniciales: articulosActuales,
    ),
  );
}

class _ArticulosSelectorSheet extends ConsumerStatefulWidget {
  final List<ArticuloSeleccionado> articulosIniciales;

  const _ArticulosSelectorSheet({required this.articulosIniciales});

  @override
  ConsumerState<_ArticulosSelectorSheet> createState() =>
      _ArticulosSelectorSheetState();
}

class _ArticulosSelectorSheetState
    extends ConsumerState<_ArticulosSelectorSheet> {
  late final Map<String, int> _cantidades;
  String _query = '';
  CategoriaArticulo? _categoriaFiltro;

  @override
  void initState() {
    super.initState();
    _cantidades = {
      for (var a in widget.articulosIniciales) a.articulo.id: a.cantidad
    };
  }

  // Mapa id -> cantidad actual
  int _cantidad(String id) => _cantidades[id] ?? 0;

  void _incrementar(String id) {
    setState(() => _cantidades[id] = _cantidad(id) + 1);
  }

  void _decrementar(String id) {
    final n = _cantidad(id) - 1;
    setState(() => n <= 0 ? _cantidades.remove(id) : _cantidades[id] = n);
  }

  List<ArticuloCatalogo> get _articulosFiltrados {
    var lista = TarifaEngine.catalogo;
    if (_categoriaFiltro != null) {
      lista = lista.where((a) => a.categoria == _categoriaFiltro).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      lista = lista
          .where((a) => a.nombre.toLowerCase().contains(q) || a.id.contains(q))
          .toList();
    }
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final seleccionados = _cantidades.values.fold<int>(0, (a, b) => a + b);

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Handle + Título ──────────────────────────────────────────
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Artículos del servicio',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (_cantidades.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: MuevexTheme.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$seleccionados art.',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Buscador ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar artículo...',
                prefixIcon: const Icon(Icons.search, size: 22),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 12),

          // ── Chips de categoría ───────────────────────────────────────
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _CategoriaChip(
                  label: 'Todos',
                  selected: _categoriaFiltro == null,
                  onTap: () => setState(() => _categoriaFiltro = null),
                ),
                const SizedBox(width: 8),
                ...CategoriaArticulo.values
                    .where((c) =>
                        TarifaEngine.catalogo.any((a) => a.categoria == c))
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _CategoriaChip(
                            label: _labelCategoria(c),
                            selected: _categoriaFiltro == c,
                            onTap: () => setState(() => _categoriaFiltro = c),
                          ),
                        )),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Lista de artículos ───────────────────────────────────────
          Expanded(
            child: _articulosFiltrados.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No hay artículos',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey.shade600)),
                        const SizedBox(height: 4),
                        Text('Prueba otra búsqueda o categoría',
                            style: TextStyle(color: Colors.grey.shade500)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _articulosFiltrados.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _ArticuloTile(
                      articulo: _articulosFiltrados[i],
                      cantidad: _cantidad(_articulosFiltrados[i].id),
                      onIncrementar: () =>
                          _incrementar(_articulosFiltrados[i].id),
                      onDecrementar: () =>
                          _decrementar(_articulosFiltrados[i].id),
                    ),
                  ),
          ),

          // ── Botón confirmar ──────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancelar',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _cantidades.isEmpty
                          ? null
                          : () {
                              final seleccion = _cantidades.entries
                                  .map((e) => ArticuloSeleccionado(
                                      TarifaEngine.articuloPorId(e.key)!,
                                      e.value))
                                  .toList();
                              Navigator.pop(context, seleccion);
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: MuevexTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Confirmar',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _labelCategoria(CategoriaArticulo c) {
  switch (c) {
    case CategoriaArticulo.muebleria:
      return 'Muebles';
    case CategoriaArticulo.electrodomestico:
      return 'Electrodomésticos';
    case CategoriaArticulo.electronica:
      return 'TV / Electrónica';
    case CategoriaArticulo.climatizacion:
      return 'Climatización';
    case CategoriaArticulo.construccion:
      return 'Construcción';
    case CategoriaArticulo.bulto:
      return 'Bultos';
    case CategoriaArticulo.caja:
      return 'Cajas';
    case CategoriaArticulo.fragil:
      return 'Frágil';
    case CategoriaArticulo.otro:
      return 'Otros';
  }
}

class _CategoriaChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoriaChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: MuevexTheme.primaryColor.withValues(alpha: 0.12),
      checkmarkColor: MuevexTheme.primaryColor,
      labelStyle: TextStyle(
          color: selected ? MuevexTheme.primaryColor : Colors.grey.shade700),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(
          color: selected ? MuevexTheme.primaryColor : Colors.transparent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _ArticuloTile extends StatelessWidget {
  final ArticuloCatalogo articulo;
  final int cantidad;
  final VoidCallback onIncrementar;
  final VoidCallback onDecrementar;

  const _ArticuloTile({
    required this.articulo,
    required this.cantidad,
    required this.onIncrementar,
    required this.onDecrementar,
  });

  @override
  Widget build(BuildContext context) {
    final tieneRecargo = articulo.recargo > 0;
    final enSeleccion = cantidad > 0;

    return Container(
      decoration: BoxDecoration(
        color: enSeleccion
            ? MuevexTheme.primaryColor.withValues(alpha: 0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enSeleccion ? MuevexTheme.primaryColor : Colors.grey.shade200,
          width: enSeleccion ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Icono por categoría
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color:
                    _colorCategoria(articulo.categoria).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_iconoCategoria(articulo.categoria),
                  color: _colorCategoria(articulo.categoria), size: 24),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          articulo.nombre,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (tieneRecargo)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: MuevexTheme.warningColor
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+${money(articulo.recargo)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: MuevexTheme.warningColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${articulo.pesoKg.toStringAsFixed(1)} kg · ${articulo.volumenM3.toStringAsFixed(2)} m³',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (articulo.fragil) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.broken_image_outlined,
                            size: 12, color: MuevexTheme.errorColor),
                        const SizedBox(width: 4),
                        Text('Frágil',
                            style: TextStyle(
                                fontSize: 11,
                                color: MuevexTheme.errorColor,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Contador cantidad
            if (enSeleccion) ...[
              const SizedBox(width: 8),
              _ContadorCantidad(
                cantidad: cantidad,
                onIncrementar: onIncrementar,
                onDecrementar: onDecrementar,
              ),
            ] else ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                height: 36,
                child: FilledButton(
                  onPressed: onIncrementar,
                  style: FilledButton.styleFrom(
                    backgroundColor: MuevexTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Añadir',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
}

class _ContadorCantidad extends StatelessWidget {
  final int cantidad;
  final VoidCallback onIncrementar;
  final VoidCallback onDecrementar;

  const _ContadorCantidad({
    required this.cantidad,
    required this.onIncrementar,
    required this.onDecrementar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onDecrementar,
            icon: const Icon(Icons.remove, size: 18),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
          Text(
            '$cantidad',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          IconButton(
            onPressed: onIncrementar,
            icon: const Icon(Icons.add, size: 18),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        ],
      ),
    );
  }
}
