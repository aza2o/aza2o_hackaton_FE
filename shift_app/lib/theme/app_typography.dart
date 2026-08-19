import 'package:flutter/widgets.dart';

/// Figma 텍스트 스타일 19종을 그대로 옮긴 것. 이름·크기·굵기·줄간격이
/// Style Guide 원본과 1:1 대응한다 (Figma 목업은 Noto Sans KR 대체본으로
/// 만들었지만, 실제 앱은 Pretendard를 그대로 쓴다).
///
/// `height`는 Flutter TextStyle 관례대로 fontSize 배수다 — Figma의
/// "줄간격 120%"는 `height: 1.2`에 대응한다.
class AppTypography {
  AppTypography._();

  static const _family = 'Pretendard';

  static const heading01 = TextStyle(
      fontFamily: _family, fontSize: 32, fontWeight: FontWeight.w700, height: 1.2);
  static const heading02 = TextStyle(
      fontFamily: _family, fontSize: 28, fontWeight: FontWeight.w700, height: 1.2);
  static const heading03 = TextStyle(
      fontFamily: _family, fontSize: 24, fontWeight: FontWeight.w700, height: 1.2);
  static const heading04 = TextStyle(
      fontFamily: _family, fontSize: 22, fontWeight: FontWeight.w700, height: 1.2);

  static const subtitle01 = TextStyle(
      fontFamily: _family, fontSize: 20, fontWeight: FontWeight.w600, height: 1.2);
  static const subtitle02 = TextStyle(
      fontFamily: _family, fontSize: 18, fontWeight: FontWeight.w600, height: 1.2);
  static const subtitle03 = TextStyle(
      fontFamily: _family, fontSize: 16, fontWeight: FontWeight.w600, height: 1.2);
  static const subtitle04 = TextStyle(
      fontFamily: _family, fontSize: 14, fontWeight: FontWeight.w600, height: 1.2);

  static const body01 = TextStyle(
      fontFamily: _family, fontSize: 16, fontWeight: FontWeight.w400, height: 1.6);
  static const body02 = TextStyle(
      fontFamily: _family, fontSize: 14, fontWeight: FontWeight.w400, height: 1.6);

  static const caption01 = TextStyle(
      fontFamily: _family, fontSize: 14, fontWeight: FontWeight.w400, height: 1.4);
  static const caption02 = TextStyle(
      fontFamily: _family, fontSize: 12, fontWeight: FontWeight.w400, height: 1.4);
  static const caption03 = TextStyle(
      fontFamily: _family, fontSize: 10, fontWeight: FontWeight.w400, height: 1.4);

  static const button01 = TextStyle(
      fontFamily: _family, fontSize: 20, fontWeight: FontWeight.w700, height: 1.4);
  static const button02 = TextStyle(
      fontFamily: _family, fontSize: 18, fontWeight: FontWeight.w600, height: 1.2);
  static const button03 = TextStyle(
      fontFamily: _family, fontSize: 16, fontWeight: FontWeight.w700, height: 1.4);
  static const button04 = TextStyle(
      fontFamily: _family, fontSize: 16, fontWeight: FontWeight.w400, height: 1.4);
  static const button05 = TextStyle(
      fontFamily: _family, fontSize: 14, fontWeight: FontWeight.w700, height: 1.4);
  static const button06 = TextStyle(
      fontFamily: _family, fontSize: 14, fontWeight: FontWeight.w400, height: 1.4);
}
