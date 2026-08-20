// 로그인/회원가입 공용 입력 필드. 이 앱에 텍스트 입력 폼이 여기 처음
// 생겨서(다른 화면은 선택형 UI 위주) 기존 카드류(`_ShiftTimingRow`,
// `_ChoiceRow`)와 같은 라운드·회색 보더 톤으로 새로 맞췄다.
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    // 라운드를 크게, 세로 여백을 넉넉하게 — 입력칸이 납작하면 손가락으로
    // 누르기도 불편하고 화면이 사무적으로 보인다.
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.gray100),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Text(label, style: AppTypography.subtitle04),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: AppTypography.body02,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.grayWhite,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
                borderSide: const BorderSide(color: AppColors.primary500, width: 1.5)),
            errorBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.error01)),
            focusedErrorBorder:
                border.copyWith(borderSide: const BorderSide(color: AppColors.error01, width: 1.5)),
          ),
        ),
      ],
    );
  }
}
