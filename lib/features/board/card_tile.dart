import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/board.dart';
import '../../theme.dart';

class CardTile extends StatefulWidget {
  const CardTile({super.key, required this.card, required this.onTap});
  final SymbolCard card;
  final VoidCallback onTap;

  @override
  State<CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<CardTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.card.labels['en'] ?? '';
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _pressed ? BoloTheme.cardPressed : BoloTheme.card,
          border: Border.all(color: BoloTheme.cardBorder, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(children: [
          Expanded(child: _image()),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: BoloTheme.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _image() {
    final photo = widget.card.photoPath;
    if (photo != null) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(photo), fit: BoxFit.cover, width: double.infinity));
    }
    final asset = widget.card.symbolAsset;
    if (asset != null) return SvgPicture.asset(asset);
    return const SizedBox.shrink();
  }
}
