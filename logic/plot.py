"""
데모 시각화 — 서버에서 PNG로 렌더링한다.

Flutter의 fl_chart로 액토그램을 재구현하지 않는다.
matplotlib이 더 잘 그리고, 클라이언트는 Image.network() 한 줄이면 된다.
fl_chart는 인터랙션이 필요한 것(각성도 곡선, 입면잠복기 추이)에만 쓴다.

⚠️ 절대 lux 비교 금지 (광센서 성능 비교, PubMed 41230818:
   21명 1주 동시 착용 시 24h 평균 lux가 ActiGraph 77.3 vs ActLumus 515.0).
   따라서 액토그램의 조도는 log 스케일 상대 표현으로만 그린다.
"""

from __future__ import annotations

import base64
import io

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from .phase import PhaseEnsemble


def _png(fig) -> bytes:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=140, bbox_inches="tight",
                facecolor="white")
    plt.close(fig)
    return buf.getvalue()


def actogram(t: np.ndarray, light: np.ndarray, ensemble: PhaseEnsemble | None = None,
             title: str = "Light exposure & DLMO") -> bytes:
    """이중 플롯 액토그램. 행=일, 열=시각."""
    days = int(np.ceil(t[-1] / 24.0))
    per_day = int(24.0 / (t[1] - t[0]))

    fig, ax = plt.subplots(figsize=(11, max(3.0, days * 0.42)))

    for d in range(days):
        row = light[d * per_day:(d + 1) * per_day]
        if len(row) < per_day:
            row = np.pad(row, (0, per_day - len(row)))
        nxt = light[(d + 1) * per_day:(d + 2) * per_day]
        if len(nxt) < per_day:
            nxt = np.pad(nxt, (0, per_day - len(nxt)))

        pair = np.concatenate([row, nxt])
        norm = np.log10(np.clip(pair, 1.0, None))
        norm = norm / max(norm.max(), 1e-9)
        x = np.linspace(0, 48, len(pair))
        ax.fill_between(x, d + 1, d + 1 - norm * 0.85, step="mid",
                        color="#f2b134", linewidth=0)

    if ensemble is not None:
        colors = {"Hannay19": "#c0392b", "Hannay19TP": "#8e44ad",
                  "Forger99": "#2980b9", "Jewett99": "#16a085"}
        for name, res in ensemble.results.items():
            xs, ys = [], []
            for dl in res.dlmos:
                d = int(dl // 24)
                if d >= days:
                    continue
                xs.append(dl % 24.0)
                ys.append(d + 0.55)
                xs.append(dl % 24.0 + 24.0)
                ys.append(d + 0.55)
            ax.scatter(xs, ys, s=14, color=colors.get(name, "#555"),
                       label=name, zorder=5,
                       alpha=1.0 if name == "Hannay19" else 0.55)
        ax.legend(loc="upper right", fontsize=8, ncol=4, framealpha=0.9)

    ax.set_xlim(0, 48)
    ax.set_ylim(days + 0.2, 0.1)
    ax.set_xticks(range(0, 49, 6))
    ax.set_yticks([d + 0.5 for d in range(days)])
    ax.set_yticklabels([f"D{d + 1}" for d in range(days)], fontsize=8)
    ax.set_xlabel("Clock time (double-plotted)")
    ax.set_title(title, fontsize=11)
    ax.grid(axis="x", alpha=0.15)
    return _png(fig)


def alertness_curve(t: np.ndarray, alert: np.ndarray,
                    risk: list[tuple[float, float]] | None = None) -> bytes:
    """각성도 곡선. 값은 상대 스케일이므로 y축 눈금을 숨긴다."""
    fig, ax = plt.subplots(figsize=(11, 2.8))
    ax.plot(t / 24.0, alert, color="#2c3e50", linewidth=1.2)
    for a, b in (risk or []):
        ax.axvspan(a / 24.0, b / 24.0, color="#e74c3c", alpha=0.16, linewidth=0)
    ax.set_xlabel("Day")
    ax.set_ylabel("Alertness (relative)")
    ax.set_yticks([])
    ax.grid(alpha=0.15)
    ax.set_title("Predicted alertness — Two-Process approximation", fontsize=10)
    return _png(fig)


def spread_chart(ensemble: PhaseEnsemble) -> bytes:
    """모델 간 DLMO 분산. '단일 모델에 베팅하지 않는다'의 시각적 증거."""
    spread = ensemble.spread_hours()
    fig, ax = plt.subplots(figsize=(11, 2.4))
    ax.bar(range(1, len(spread) + 1), spread, color="#7f8c8d")
    ax.axhline(1.0, color="#c0392b", linestyle="--", linewidth=1,
               label="1h threshold (Hannay 2019)")
    ax.set_xlabel("Day")
    ax.set_ylabel("Model spread (h)")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.15)
    return _png(fig)


def to_data_uri(png: bytes) -> str:
    return "data:image/png;base64," + base64.b64encode(png).decode()
