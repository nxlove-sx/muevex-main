import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final String? initialValue;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final void Function(String?)? onSaved;
  final void Function(String?)? onChanged;
  final bool obscureText;
  final String? hintText;
  final Widget? suffixIcon;
  final IconData? prefixIcon;
  final TextEditingController? controller;
  final int? maxLines;

  const CustomTextField({
    super.key,
    required this.label,
    this.initialValue,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.onSaved,
    this.onChanged,
    this.obscureText = false,
    this.hintText,
    this.suffixIcon,
    this.prefixIcon,
    this.controller,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          initialValue: initialValue,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          onSaved: onSaved,
          onChanged: onChanged,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hintText,
            suffixIcon: suffixIcon,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
          ),
        ),
      ],
    );
  }
}