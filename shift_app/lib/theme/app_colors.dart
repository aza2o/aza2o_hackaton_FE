import 'package:flutter/widgets.dart';

/// Figma "Design Colors"/"System Colors" 변수 컬렉션을 그대로 옮긴 것.
/// 값은 스타일 가이드 파일에서 직접 추출했으며, 여기서 값을 바꾸면 안 된다
/// — 바꿔야 하면 Figma 쪽 변수를 먼저 바꾸고 그 값을 다시 옮길 것.
class AppColors {
  AppColors._();

  // ── Primary (Design Colors) ──────────────────────────────
  static const primary900 = Color(0xFFFC7318);
  static const primary800 = Color(0xFFFD921D);
  static const primary700 = Color(0xFFFDA220);
  static const primary600 = Color(0xFFFEB523);
  static const primary500 = Color(0xFFFFC228); // Main
  static const primary400 = Color(0xFFFFCB3B);
  static const primary300 = Color(0xFFFFD65A);
  static const primary200 = Color(0xFFFFE188);
  static const primary100 = Color(0xFFFFECB6);
  static const primary50 = Color(0xFFFFF8E2);

  // ── Gray (System Colors) ─────────────────────────────────
  static const grayBlack = Color(0xFF000000);
  static const gray900 = Color(0xFF111111);
  static const gray800 = Color(0xFF313131);
  static const gray700 = Color(0xFF4F4F4F);
  static const gray600 = Color(0xFF626262);
  static const gray500 = Color(0xFF898989);
  static const gray400 = Color(0xFFAAAAAA);
  static const gray300 = Color(0xFFCFCFCF);
  static const gray200 = Color(0xFFE1E1E1);
  static const gray100 = Color(0xFFEEEEEE);
  static const gray50 = Color(0xFFF7F7F7);
  static const grayWhite = Color(0xFFFFFFFF);

  // ── 상태색 ────────────────────────────────────────────────
  static const error01 = Color(0xFFFF383C);
  static const error02 = Color(0xFFFF4245);
  static const error03 = Color(0xFFFF6165);
  static const warning01 = Color(0xFFFFCC00);
  static const warning02 = Color(0xFFFFD600);
  static const warning03 = Color(0xFFFEDF43);
  static const success01 = Color(0xFF34C759);
  static const success02 = Color(0xFF30D158);
  static const success03 = Color(0xFF4AE968);
  static const information01 = Color(0xFF0088FF);
  static const information02 = Color(0xFF0091FF);
  static const information03 = Color(0xFF5CB8FF);

  static const background = Color(0xFFFAFAFA);

  // ── 시맨틱 (전부 위 원시값의 별칭 — Figma와 동일 매핑 유지) ──
  static const textPrimary = gray900;
  static const textSecondary = gray700;
  static const textTertiary = gray600;
  static const textPlaceholder = gray500;
  static const textInverse = grayWhite;
  static const borderStrong = gray500;
  static const borderDefault = gray400;
  static const borderDeactivated = gray300;
  static const borderUseless = gray200;
}
