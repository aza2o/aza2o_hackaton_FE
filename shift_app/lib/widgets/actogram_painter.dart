import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 이중 플롯(double-plot) 액토그램 한 행의 데이터.
class ActogramRow {
  const ActogramRow({
    required this.label,
    required this.sleep,
    required this.work,
    required this.dlmoHour,
    this.riskWindows = const [],
    this.idealBedtimeHour,
  });
  final String label;
  final List<(double, double)> sleep; // (시작, 끝) — 0~48h 축
  final List<(double, double)> work;
  final double dlmoHour;
  /// Process S/C 기반 각성도 하위 15% 구간(`pressure.dart`의 riskWindows).
  /// 트랙 위에 옅은 음영으로 겹쳐 그린다.
  final List<(double, double)> riskWindows;
  /// 근무표 기반 목표 취침(§2-① `idealSleepTimes`), 0~48h 축. null이면
  /// 폴백에 쓸 최근 수면 이력이 없어(양쪽 다 오프인 첫날 등) 표시 안 함.
  final double? idealBedtimeHour;
}

/// 기존 개발기획서 §5-3이 요구한 `CustomPainter` 기반 액토그램.
/// Figma 신규 파일 `13:15` 카드의 실제 렌더링 구현.
class ActogramPainter extends CustomPainter {
  ActogramPainter(this.rows);
  final List<ActogramRow> rows;

  static const _rowH = 30.0;
  static const _rowGap = 6.0;
  static const _labelW = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    final trackW = size.width - _labelW;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final y = i * (_rowH + _rowGap);

      textPainter.text = TextSpan(
        text: row.label,
        style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, y + _rowH / 2 - 6));

      final trackRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(_labelW, y, trackW, _rowH),
        const Radius.circular(8),
      );
      canvas.drawRRect(trackRect, Paint()..color = AppColors.gray50);

      double px(double h) => _labelW + (h / 48.0) * trackW;

      // 위험구간 음영 — 다른 요소보다 먼저 그려서 맨 아래 깔린다.
      final riskPaint = Paint()..color = AppColors.error01.withValues(alpha: 0.14);
      final riskDotPaint = Paint()..color = AppColors.error01;
      for (final (s, e) in row.riskWindows) {
        final double w = (px(e) - px(s)).clamp(1, trackW);
        canvas.drawRect(Rect.fromLTWH(px(s), y, w, _rowH), riskPaint);
        if (w >= 10) {
          canvas.drawCircle(Offset(px(s) + w / 2, y + _rowH - 6), 2.5, riskDotPaint);
        }
      }

      // 하루 경계(24h) — 이중 플롯의 두 날짜를 시각적으로 구분.
      canvas.drawLine(
        Offset(px(24), y),
        Offset(px(24), y + _rowH),
        Paint()
          ..color = AppColors.gray300
          ..strokeWidth = 1,
      );

      final sleepPaint = Paint()..color = AppColors.gray700;
      for (final (s, e) in row.sleep) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(px(s), y, (px(e) - px(s)).clamp(2, trackW), _rowH),
              const Radius.circular(8)),
          sleepPaint,
        );
      }

      final workPaint = Paint()..color = AppColors.primary300;
      for (final (s, e) in row.work) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(px(s), y, (px(e) - px(s)).clamp(2, trackW), _rowH),
              const Radius.circular(8)),
          workPaint,
        );
      }

      final dlmoX = px(row.dlmoHour);
      canvas.drawCircle(Offset(dlmoX, y + _rowH / 2), 4,
          Paint()..color = AppColors.primary900);
      canvas.drawCircle(
          Offset(dlmoX, y + _rowH / 2),
          4,
          Paint()
            ..color = AppColors.grayWhite
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      // 목표 취침(이상적 취침) 기준선 — 실제 수면 블록과의 어긋남이
      // 곧 넛지가 필요한 정도(gapMinutes)다.
      final ideal = row.idealBedtimeHour;
      if (ideal != null) {
        final idealX = px(ideal);
        canvas.drawLine(
          Offset(idealX, y - 2),
          Offset(idealX, y + _rowH + 2),
          Paint()
            ..color = AppColors.information01
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ActogramPainter oldDelegate) =>
      oldDelegate.rows != rows;
}

/// [ActogramPainter]를 실제 높이에 맞춰 그리는 위젯.
class ActogramView extends StatelessWidget {
  const ActogramView({super.key, required this.rows});
  final List<ActogramRow> rows;

  @override
  Widget build(BuildContext context) {
    final height = rows.length * (ActogramPainter._rowH + ActogramPainter._rowGap);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: ActogramPainter(rows)),
    );
  }
}

/// [ActogramView] 위에 붙는 시간축 — 0/6/12/18/24시(다음날 0/6/12/18/24시)
/// 눈금. 트랙 좌표 변환은 [ActogramPainter]와 동일해야 눈금이 블록과 맞는다.
class ActogramTimeAxis extends StatelessWidget {
  const ActogramTimeAxis({super.key});

  static const _ticks = [0.0, 6.0, 12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0];

  String _tickLabel(double h) => (h == 0 ? 0 : (h % 24 == 0 ? 24 : h % 24)).round().toString();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackW = constraints.maxWidth - ActogramPainter._labelW;
        return SizedBox(
          height: 14,
          child: Stack(
            children: [
              for (final h in _ticks)
                Positioned(
                  left: ActogramPainter._labelW + (h / 48.0) * trackW - 8,
                  width: 16,
                  child: Text(
                    _tickLabel(h),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9, color: AppColors.textPlaceholder),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
