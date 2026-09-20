"""Analyze stored BC AI knowledge evaluation artifacts and render reports."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import json
from pathlib import Path
import statistics
from typing import Any, Iterable


SCHEMA_VERSION = "1.0"
DIMENSIONS = (
    "correctness",
    "completeness_actionability",
    "scope_fit",
    "uncertainty_safety",
    "evidence_grounding",
)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read JSON '{path}': {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object in '{path}'.")
    version = str(value.get("schema_version", ""))
    if version.split(".", 1)[0] != SCHEMA_VERSION.split(".", 1)[0]:
        raise ValueError(f"Unsupported schema version '{version}' in '{path}'.")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_directory(path: Path) -> list[dict[str, Any]]:
    if not path.is_dir():
        return []
    return [load_json(item) for item in sorted(path.glob("*.json"))]


def deblind_winner(judgment: dict[str, Any]) -> str:
    winner = judgment.get("winner", "unsure")
    if winner in ("tie", "unsure"):
        return winner
    return str(judgment.get("blind_mapping", {}).get(winner, "unsure"))


def material_errors(judgment: dict[str, Any]) -> list[Any]:
    errors = list(judgment.get("material_errors") or [])
    evidence = judgment.get("evidence", {})
    if isinstance(evidence, dict):
        response = evidence.get("response", {})
        if isinstance(response, dict):
            errors.extend(response.get("material_errors") or [])
            errors.extend(
                claim
                for claim in response.get("claims") or []
                if isinstance(claim, dict) and claim.get("material_error")
            )
    return errors


def consensus(judgments: list[dict[str, Any]]) -> dict[str, Any]:
    votes = [deblind_winner(item) for item in judgments]
    counts = Counter(votes)
    decisive = [(name, count) for name, count in counts.items() if name not in ("unsure",)]
    decisive.sort(key=lambda item: (-item[1], item[0]))
    winner, winner_count = decisive[0] if decisive else ("unsure", 0)
    required = len(judgments) // 2 + 1
    errors = [error for item in judgments for error in material_errors(item)]
    if errors or winner_count < required or winner == "unsure":
        confidence = "low"
        outcome = "inconclusive"
        human_required = True
    else:
        confidence = "high" if winner_count == len(judgments) else "medium"
        outcome = "tie" if winner == "tie" else ("docs_win" if winner.endswith("1") else "code_win")
        human_required = False
    return {
        "outcome": outcome,
        "winning_arm": None if outcome in ("tie", "inconclusive") else winner,
        "confidence": confidence,
        "votes": dict(sorted(counts.items())),
        "judge_count": len(judgments),
        "material_errors": errors,
        "human_review_required": human_required,
    }


def deblinded_scores(judgments: Iterable[dict[str, Any]]) -> dict[str, dict[str, float | None]]:
    values: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    for judgment in judgments:
        mapping = judgment.get("blind_mapping", {})
        scores = judgment.get("scores", {})
        if isinstance(scores, dict):
            for label in ("A", "B"):
                arm = mapping.get(label)
                arm_scores = scores.get(label, {})
                if arm and isinstance(arm_scores, dict):
                    for dimension, score in arm_scores.items():
                        if isinstance(score, (int, float)):
                            values[str(arm)][dimension].append(float(score))
        evidence = judgment.get("evidence", {})
        response = evidence.get("response", {}) if isinstance(evidence, dict) else {}
        grounding = response.get("evidence_grounding", {}) if isinstance(response, dict) else {}
        if isinstance(grounding, dict):
            for label in ("A", "B"):
                arm = mapping.get(label)
                score = grounding.get(label)
                if arm and isinstance(score, (int, float)):
                    values[str(arm)]["evidence_grounding"].append(float(score))
    arms = sorted(values)
    return {
        arm: {
            dimension: round(statistics.mean(values[arm][dimension]), 3)
            if values[arm].get(dimension)
            else None
            for dimension in DIMENSIONS
        }
        for arm in arms
    }


def metric_value(run: dict[str, Any], name: str) -> tuple[float | None, str]:
    metric = run.get("consumption", {}).get(name)
    if not isinstance(metric, dict):
        return None, "unavailable"
    value = metric.get("value")
    return (float(value), str(metric.get("status", "unavailable"))) if isinstance(value, (int, float)) else (None, str(metric.get("status", "unavailable")))


def compare_consumption(runs: list[dict[str, Any]], left: str, right: str) -> dict[str, Any]:
    result: dict[str, Any] = {}
    metric_names = (
        "wall_time_seconds",
        "output_bytes",
        "output_tokens_estimate",
        "input_tokens",
        "output_tokens",
        "cache_read_tokens",
        "cache_write_tokens",
        "reasoning_tokens",
        "total_nano_aiu",
        "request_multiplier_sum",
        "credits",
    )
    for name in metric_names:
        arm_values: dict[str, list[float]] = {left: [], right: []}
        statuses: list[str] = []
        for run in runs:
            if run.get("arm") not in arm_values:
                continue
            value, status = metric_value(run, name)
            statuses.append(status)
            if value is not None:
                arm_values[str(run["arm"])].append(value)
        if not arm_values[left] or not arm_values[right]:
            result[name] = {"status": "unavailable", "left": None, "right": None, "delta": None}
            continue
        left_mean = statistics.mean(arm_values[left])
        right_mean = statistics.mean(arm_values[right])
        status = "measured" if statuses and all(item == "measured" for item in statuses) else "partial"
        result[name] = {
            "status": status,
            "left": round(left_mean, 3),
            "right": round(right_mean, 3),
            "delta": round(right_mean - left_mean, 3),
        }
    return result


def question_feedback(primary: dict[str, Any]) -> list[dict[str, Any]]:
    if primary["outcome"] == "inconclusive":
        return [{
            "category": "judge_uncertainty",
            "priority": "high",
            "evidence": primary,
            "next_action": "Human-review the answers and critical claims before changing documentation or the skill.",
        }]
    if primary["outcome"] == "code_win":
        return [{
            "category": "inaccurate_or_stale_knowledge",
            "priority": "high",
            "evidence": primary,
            "next_action": "Inspect docs-assisted claims against the owning source and tests.",
        }]
    if primary["outcome"] == "tie":
        return [{
            "category": "code_only_sufficient",
            "priority": "low",
            "evidence": primary,
            "next_action": "Keep the documentation only if it improves navigation, maintenance, or lower-cost-model results.",
        }]
    return []


def render_question_markdown(report: dict[str, Any]) -> str:
    lines = [
        f"# Evaluation: {report['question_id']}",
        "",
        f"**Outcome:** {report['outcome']}  ",
        f"**Confidence:** {report['quality']['primary_consensus']['confidence']}  ",
        f"**Human review required:** {str(report['quality']['primary_consensus']['human_review_required']).lower()}",
        "",
        "## Question",
        "",
        report["question"],
        "",
        "## Consensus",
        "",
        "```json",
        json.dumps(report["quality"], indent=2, sort_keys=True),
        "```",
        "",
        "## Consumption",
        "",
        "```json",
        json.dumps(report["consumption"], indent=2, sort_keys=True),
        "```",
        "",
        "## Answers",
        "",
    ]
    for arm, answers in sorted(report["answers"].items()):
        lines.extend([f"### {arm}", "", "\n\n".join(answers), ""])
    if report["feedback"]:
        lines.extend(["## Feedback", "", "```json", json.dumps(report["feedback"], indent=2, sort_keys=True), "```", ""])
    return "\n".join(lines)


def analyze_evaluation(root: Path) -> dict[str, Any]:
    manifest = load_json(root / "evaluation-manifest.json")
    runs = load_directory(root / "runs")
    judgments = load_directory(root / "judgments")
    if not runs:
        raise ValueError("No run artifacts are available.")
    if not judgments:
        raise ValueError("No judgment artifacts are available.")

    runs_by_question: dict[str, list[dict[str, Any]]] = defaultdict(list)
    judgments_by_question: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for run in runs:
        if run.get("execution", {}).get("status") == "complete":
            runs_by_question[str(run["question_id"])].append(run)
    for judgment in judgments:
        judgments_by_question[str(judgment["question_id"])].append(judgment)

    reports_root = root / "reports"
    question_root = reports_root / "questions"
    question_reports: list[dict[str, Any]] = []
    for question_record in manifest.get("questions", []):
        question_id = str(question_record["question_id"])
        question_runs = runs_by_question.get(question_id, [])
        question_judgments = judgments_by_question.get(question_id, [])
        question_text = str(question_record.get("question", ""))
        comparisons: dict[str, Any] = {}
        for comparison in sorted({str(item["comparison"]) for item in question_judgments}):
            selected = [item for item in question_judgments if item["comparison"] == comparison]
            comparisons[comparison] = consensus(selected)
        primary = comparisons.get("C0_vs_C1", {"outcome": "inconclusive", "confidence": "low", "human_review_required": True})
        report = {
            "schema_version": SCHEMA_VERSION,
            "evaluation_id": manifest["evaluation_id"],
            "question_id": question_id,
            "report_type": "question",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "outcome": primary["outcome"],
            "question": question_text,
            "provenance": {
                "source": manifest.get("source"),
                "workspace_isolation": manifest.get("workspace_isolation"),
                "workspaces": manifest.get("workspaces"),
            },
            "answers": {
                arm: [str(item.get("response_text", "")) for item in question_runs if item.get("arm") == arm]
                for arm in sorted({str(item.get("arm")) for item in question_runs})
            },
            "quality": {
                "primary_consensus": primary,
                "comparisons": comparisons,
                "mean_scores_by_arm": deblinded_scores(question_judgments),
            },
            "consumption": {
                "C0_vs_C1": compare_consumption(question_runs, "C0", "C1"),
            },
            "feedback": question_feedback(primary),
        }
        if any(item.get("arm") == "E0" for item in question_runs):
            report["consumption"]["E0_vs_E1"] = compare_consumption(question_runs, "E0", "E1")
        write_json(question_root / f"{question_id}.json", report)
        (question_root / f"{question_id}.md").write_text(render_question_markdown(report), encoding="utf-8")
        question_reports.append(report)

    outcome_counts = Counter(item["outcome"] for item in question_reports)
    aggregate_outcome = next(iter(outcome_counts)) if len(outcome_counts) == 1 else "mixed"
    aggregate = {
        "schema_version": SCHEMA_VERSION,
        "evaluation_id": manifest["evaluation_id"],
        "question_id": None,
        "report_type": "aggregate",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "outcome": aggregate_outcome,
        "sample_size": len(question_reports),
        "study_type": "case_study" if len(question_reports) < 10 else "benchmark",
        "outcome_counts": dict(sorted(outcome_counts.items())),
        "human_review_required": any(item["quality"]["primary_consensus"]["human_review_required"] for item in question_reports),
        "quality": {"questions": [{"question_id": item["question_id"], "outcome": item["outcome"]} for item in question_reports]},
        "consumption": {"note": "See per-question measured, partial, and unavailable metric states."},
        "feedback": [finding for item in question_reports for finding in item["feedback"]],
    }
    write_json(reports_root / "aggregate.json", aggregate)
    markdown = [
        "# BC AI knowledge evaluation aggregate",
        "",
        f"**Evaluation:** {aggregate['evaluation_id']}  ",
        f"**Questions:** {aggregate['sample_size']}  ",
        f"**Study type:** {aggregate['study_type']}  ",
        f"**Outcome:** {aggregate['outcome']}",
        "",
        "## Outcomes",
        "",
        "```json",
        json.dumps(aggregate["outcome_counts"], indent=2, sort_keys=True),
        "```",
        "",
        "Small samples are descriptive case studies and do not establish statistical significance.",
        "",
    ]
    (reports_root / "aggregate.md").write_text("\n".join(markdown), encoding="utf-8")
    return aggregate


def aggregate_across_apps(roots: list[Path], output: Path) -> None:
    aggregates = [load_json(root / "reports" / "aggregate.json") for root in roots]
    counts: Counter[str] = Counter()
    for aggregate in aggregates:
        counts.update(aggregate.get("outcome_counts", {}))
    report = {
        "schema_version": SCHEMA_VERSION,
        "evaluation_id": "cross-app",
        "question_id": None,
        "report_type": "cross-app",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "outcome": "mixed" if len(counts) > 1 else (next(iter(counts)) if counts else "inconclusive"),
        "evaluation_count": len(aggregates),
        "sample_size": sum(int(item.get("sample_size", 0)) for item in aggregates),
        "outcome_counts": dict(sorted(counts.items())),
        "quality": {},
        "consumption": {"status": "not_combined", "reason": "Per-run model and protocol compatibility must be reviewed before combining consumption."},
        "feedback": [],
    }
    write_json(output, report)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evaluation-root", required=True, type=Path)
    parser.add_argument("--additional-evaluation-root", action="append", default=[], type=Path)
    args = parser.parse_args()
    aggregate = analyze_evaluation(args.evaluation_root)
    if args.additional_evaluation_root:
        roots = [args.evaluation_root, *args.additional_evaluation_root]
        aggregate_across_apps(roots, args.evaluation_root / "reports" / "cross-app.json")
    print(
        f"Generated reports for {aggregate['sample_size']} question(s): "
        f"{args.evaluation_root / 'reports'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())