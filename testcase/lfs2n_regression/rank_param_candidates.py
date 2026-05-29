#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


METRIC_FILE_PATTERNS = (
    "pc_lfs2n_metrics_*.json",
    "pc_lfs2n_baseline_metrics.json",
)


def _safe_get(dct, *keys, default=0):
    node = dct
    for key in keys:
        if not isinstance(node, dict):
            return default
        node = node.get(key)
    return default if node is None else node


def _candidate_id_from_metrics_file(path: Path) -> str:
    name = path.stem
    if name.startswith("pc_lfs2n_metrics_"):
        return name.replace("pc_lfs2n_metrics_", "", 1)
    if name == "pc_lfs2n_baseline_metrics":
        return "baseline"
    return name.replace("pc_lfs2n_", "", 1)


def _normalize_candidate(candidate_id: str, metrics: dict, source: str, config: dict | None = None) -> dict:
    writeback = metrics.get("writeback", {})
    reasons = writeback.get("reason_counts", {})
    cache_pool = metrics.get("cache_pool", {})

    latency_ms = int(metrics.get("total_latency_ms", 0))
    stall_total_ms = _safe_get(writeback, "trace_total_stall_us", default=0) / 1000.0
    stall_max_ms = _safe_get(writeback, "trace_max_stall_us", default=0) / 1000.0
    guard_count = int(cache_pool.get("guard_count", 0))
    guard_requested_bytes = int(cache_pool.get("guard_requested_bytes", 0))
    hard_cap = int(cache_pool.get("hard_cap", 0))
    telemetry_ok = 1 if int(cache_pool.get("config_seen", 0)) > 0 else 0

    over_limit = int(reasons.get("over_limit", 0))
    pressure = int(reasons.get("pressure", 0))
    expand_fallback = int(reasons.get("expand_fallback", 0))
    unknown_reason = int(reasons.get("unknown", 0))
    flush_count = int(writeback.get("trace_count", 0))

    # Lower is better; deterministic weighted penalty.
    penalty = (
        latency_ms * 1.0
        + stall_total_ms * 0.35
        + stall_max_ms * 0.8
        + guard_count * 450
        + over_limit * 320
        + pressure * 180
        + expand_fallback * 500
        + unknown_reason * 120
        + (0 if telemetry_ok else 50000)
    )

    safety_margin_ratio = 1.0
    if hard_cap > 0 and guard_requested_bytes > 0:
        safety_margin_ratio = max(0.0, 1.0 - min(1.0, guard_requested_bytes / float(hard_cap)))

    params = {
        "budget_bytes": int(cache_pool.get("budget", 0)),
        "hard_cap_bytes": hard_cap,
        "slots": int(cache_pool.get("slots", 0)),
        "chunk_bytes": int(cache_pool.get("chunk", 0)),
    }
    if config:
        params.update(
            {
                "budget_bytes": int(config.get("LUAT_LFS2N_CACHE_POOL_BUDGET", params["budget_bytes"])),
                "slots": int(config.get("LUAT_LFS2N_CACHE_POOL_SLOTS", params["slots"])),
                "chunk_bytes": int(config.get("LUAT_LFS2N_CACHE_POOL_CHUNK", params["chunk_bytes"])),
                "file_cache_limit_bytes": int(config.get("LUAT_LFS2N_FILE_CACHE_LIMIT", 0)),
                "writeback_cadence_us": int(config.get("LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US", 0)),
                "writeback_pressure_high_pct": int(config.get("LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT", 87)),
                "writeback_pressure_low_pct": int(config.get("LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT", 62)),
                "writeback_reserve_pct": int(config.get("LUAT_LFS2N_WRITEBACK_RESERVE_PCT", 12)),
                "writeback_reserve_urgent_pct": int(config.get("LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT", 4)),
                "writeback_reserve_defer_us": int(config.get("LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US", 5000000)),
                "meta_refresh_min_interval_us": int(config.get("LUAT_LFS2N_META_REFRESH_MIN_INTERVAL_US", 0)),
                "meta_refresh_max_delay_us": int(config.get("LUAT_LFS2N_META_REFRESH_MAX_DELAY_US", 0)),
            }
        )

    return {
        "candidate_id": candidate_id,
        "source": source,
        "params": params,
        "metrics": {
            "latency_ms": latency_ms,
            "stall_total_ms": round(stall_total_ms, 3),
            "stall_max_ms": round(stall_max_ms, 3),
            "flush_count": flush_count,
            "guard_count": guard_count,
            "guard_requested_bytes": guard_requested_bytes,
            "telemetry_ok": telemetry_ok,
            "reason_counts": {
                "over_limit": over_limit,
                "pressure": pressure,
                "expand_fallback": expand_fallback,
                "unknown": unknown_reason,
            },
            "safety_margin_ratio": round(safety_margin_ratio, 4),
        },
        "ranking": {
            "penalty": round(penalty, 3),
            "score": round(-penalty, 3),
        },
    }


def load_candidates(outputs_dir: Path, matrix_input: Path | None = None) -> list[dict]:
    candidates = []

    if matrix_input and matrix_input.exists():
        matrix = json.loads(matrix_input.read_text(encoding="utf-8"))
        # Support both:
        # 1) matrix results payload: {"runs":[{"case_id","config","metrics",...},...]}
        # 2) lightweight list rows: [{"candidate_id","metrics_file"}, ...]
        if isinstance(matrix, dict) and isinstance(matrix.get("runs"), list):
            for run in matrix["runs"]:
                if not isinstance(run, dict):
                    continue
                metrics = run.get("metrics")
                if not isinstance(metrics, dict):
                    continue
                case_id = str(run.get("case_id", "unknown"))
                source = f"{matrix_input}#runs[{case_id}]"
                candidates.append(
                    _normalize_candidate(
                        case_id,
                        metrics,
                        source,
                        config=run.get("config") if isinstance(run.get("config"), dict) else None,
                    )
                )
        elif isinstance(matrix, list):
            for row in matrix:
                metrics_path = Path(row["metrics_file"])
                if not metrics_path.is_absolute():
                    from_outputs = (outputs_dir / metrics_path)
                    if from_outputs.exists():
                        metrics_path = from_outputs
                    elif matrix_input is not None:
                        metrics_path = (matrix_input.parent / metrics_path)
                    else:
                        metrics_path = from_outputs
                metrics_path = metrics_path.resolve()
                metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
                candidates.append(
                    _normalize_candidate(
                        row.get("candidate_id", _candidate_id_from_metrics_file(metrics_path)),
                        metrics,
                        str(metrics_path),
                    )
                )
    else:
        seen_ids = set()
        for pattern in METRIC_FILE_PATTERNS:
            for path in sorted(outputs_dir.glob(pattern)):
                candidate_id = _candidate_id_from_metrics_file(path)
                if candidate_id in seen_ids:
                    continue
                seen_ids.add(candidate_id)
                metrics = json.loads(path.read_text(encoding="utf-8"))
                candidates.append(_normalize_candidate(candidate_id, metrics, str(path)))

    return candidates


def rank_candidates(candidates: list[dict]) -> list[dict]:
    ranked = sorted(
        candidates,
        key=lambda x: (
            x["ranking"]["penalty"],
            x["metrics"]["latency_ms"],
            x["metrics"]["stall_max_ms"],
            x["candidate_id"],
        ),
    )
    for idx, item in enumerate(ranked, start=1):
        item["ranking"]["rank"] = idx
    return ranked


def build_recommendations(ranked: list[dict]) -> dict:
    if not ranked:
        return {
            "default_preset": None,
            "aggressive_debug_preset": None,
        }

    top = ranked[0]
    top_params = top["params"]
    base_budget = top_params.get("budget_bytes", 0)
    base_chunk = top_params.get("chunk_bytes", 4096) or 4096
    debug_budget = max(base_chunk * 4, min(base_budget, max(base_chunk * 8, base_budget // 2 if base_budget else 65536)))

    return {
        "default_preset": {
            "name": "recommended_default",
            "from_candidate": top["candidate_id"],
            "compile_time_macros": {
                "LUAT_LFS2N_CACHE_POOL_BUDGET": top_params.get("budget_bytes", 131072),
                "LUAT_LFS2N_CACHE_POOL_SLOTS": max(1, top_params.get("slots", 8)),
                "LUAT_LFS2N_CACHE_POOL_CHUNK": max(512, top_params.get("chunk_bytes", 4096)),
                "LUAT_LFS2N_FILE_CACHE_LIMIT": 65536,
                "LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US": top_params.get("writeback_cadence_us", 50000),
                "LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT": top_params.get("writeback_pressure_high_pct", 87),
                "LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT": top_params.get("writeback_pressure_low_pct", 62),
                "LUAT_LFS2N_WRITEBACK_RESERVE_PCT": top_params.get("writeback_reserve_pct", 12),
                "LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT": top_params.get("writeback_reserve_urgent_pct", 4),
                "LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US": top_params.get("writeback_reserve_defer_us", 5000000),
                "LUAT_LFS2N_META_REFRESH_MIN_INTERVAL_US": top_params.get("meta_refresh_min_interval_us", 100000),
                "LUAT_LFS2N_META_REFRESH_MAX_DELAY_US": top_params.get("meta_refresh_max_delay_us", 3000000),
            },
            "intent": "Balanced latency/stall profile with low guard pressure.",
        },
        "aggressive_debug_preset": {
            "name": "aggressive_debug",
            "from_candidate": top["candidate_id"],
            "compile_time_macros": {
                "LUAT_LFS2N_CACHE_POOL_BUDGET": int(debug_budget),
                "LUAT_LFS2N_CACHE_POOL_SLOTS": max(4, top_params.get("slots", 8)),
                "LUAT_LFS2N_CACHE_POOL_CHUNK": max(1024, top_params.get("chunk_bytes", 4096)),
                "LUAT_LFS2N_FILE_CACHE_LIMIT": max(8192, top_params.get("chunk_bytes", 4096) * 2),
                "LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US": 10000,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT": 75,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT": 50,
                "LUAT_LFS2N_WRITEBACK_RESERVE_PCT": 20,
                "LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT": 8,
                "LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US": 500000,
                "LUAT_LFS2N_META_REFRESH_MIN_INTERVAL_US": 20000,
                "LUAT_LFS2N_META_REFRESH_MAX_DELAY_US": 500000,
            },
            "intent": "Force earlier/smaller flushes to surface hotspot stalls and guard-pressure behavior quickly.",
        },
    }


def build_tradeoff_report(ranked: list[dict], recommendations: dict, top_n: int = 3) -> str:
    lines = [
        "# lfs2n Parameter Ranking Report",
        "",
        "## Ranking criteria (deterministic)",
        "- Primary objective: minimize end-to-end latency and writeback stall time.",
        "- Penalties increase for cache guard hits and writeback reasons indicating pressure/overflow.",
        "- Missing cache-pool telemetry gets a large fixed penalty to keep non-instrumented runs from winning.",
        "- Tie-breakers: lower latency, lower max stall, then lexical candidate id.",
        "",
        "## Top candidates",
        "| Rank | Candidate | Latency(ms) | Stall total(ms) | Max stall(ms) | Guards | over_limit | pressure | Safety margin | Penalty |",
        "|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for item in ranked[:max(1, top_n)]:
        m = item["metrics"]
        lines.append(
            f"| {item['ranking']['rank']} | {item['candidate_id']} | {m['latency_ms']} | {m['stall_total_ms']:.3f} | "
            f"{m['stall_max_ms']:.3f} | {m['guard_count']} | {m['reason_counts']['over_limit']} | "
            f"{m['reason_counts']['pressure']} | {m['safety_margin_ratio']:.4f} | {item['ranking']['penalty']:.3f} |"
        )

    lines.extend(
        [
            "",
            "## Preset recommendations",
            "### Recommended default preset",
            f"- Source candidate: `{recommendations['default_preset']['from_candidate']}`",
            f"- Macros: `{json.dumps(recommendations['default_preset']['compile_time_macros'], ensure_ascii=False, sort_keys=True)}`",
            f"- Rationale: {recommendations['default_preset']['intent']}",
            "",
            "### Aggressive debug preset",
            f"- Derived from candidate: `{recommendations['aggressive_debug_preset']['from_candidate']}`",
            f"- Macros: `{json.dumps(recommendations['aggressive_debug_preset']['compile_time_macros'], ensure_ascii=False, sort_keys=True)}`",
            f"- Rationale: {recommendations['aggressive_debug_preset']['intent']}",
            "",
            "## Tradeoff summary",
            "- Lower flush cadence and smaller per-file cache limit reduce burst-stall amplitude but increase flush frequency.",
            "- Larger cache budget usually improves throughput but can hide pressure issues until later; debug preset intentionally tightens this.",
            "- Guard/overflow counters are safety-margin signals: sustained non-zero values indicate headroom risk under larger workloads.",
        ]
    )
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Rank lfs2n parameter candidates and generate presets.")
    parser.add_argument("--outputs-dir", default="testcase/lfs2n_regression/outputs", help="Directory holding parser output JSON files")
    parser.add_argument("--matrix-input", help="Optional matrix artifact JSON (pc_lfs2n_matrix_results.json or list rows with metrics_file)")
    parser.add_argument("--ranking-json-out", default="testcase/lfs2n_regression/outputs/lfs2n_param_ranking.json")
    parser.add_argument("--report-md-out", default="testcase/lfs2n_regression/outputs/lfs2n_param_ranking_report.md")
    parser.add_argument("--top-n", type=int, default=3)
    args = parser.parse_args()

    outputs_dir = Path(args.outputs_dir)
    matrix_input = Path(args.matrix_input) if args.matrix_input else None
    if matrix_input is None:
        auto_matrix = outputs_dir / "pc_lfs2n_matrix_results.json"
        if auto_matrix.exists():
            matrix_input = auto_matrix
    ranking_json_out = Path(args.ranking_json_out)
    report_md_out = Path(args.report_md_out)

    candidates = load_candidates(outputs_dir, matrix_input)
    ranked = rank_candidates(candidates)
    recommendations = build_recommendations(ranked)
    report_markdown = build_tradeoff_report(ranked, recommendations, top_n=args.top_n)

    payload = {
        "criteria_version": "v1",
        "candidate_count": len(ranked),
        "ranked_candidates": ranked,
        "recommendations": recommendations,
    }

    ranking_json_out.parent.mkdir(parents=True, exist_ok=True)
    ranking_json_out.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    report_md_out.parent.mkdir(parents=True, exist_ok=True)
    report_md_out.write_text(report_markdown, encoding="utf-8")

    print(json.dumps({
        "ranking_json": str(ranking_json_out),
        "report_md": str(report_md_out),
        "default_preset": recommendations["default_preset"],
        "aggressive_debug_preset": recommendations["aggressive_debug_preset"],
    }, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
