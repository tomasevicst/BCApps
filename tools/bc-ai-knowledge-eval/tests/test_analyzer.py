from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


TOOL_ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "bc_ai_knowledge_analyzer", TOOL_ROOT / "Analyze-BcAiKnowledgeEval.py"
)
assert SPEC and SPEC.loader
ANALYZER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ANALYZER)


def judgment(winner: str, mapping: dict[str, str] | None = None, errors: list | None = None) -> dict:
    return {
        "winner": winner,
        "blind_mapping": mapping or {"A": "C0", "B": "C1"},
        "material_errors": errors or [],
        "scores": {
            "A": {"correctness": 1, "completeness_actionability": 1},
            "B": {"correctness": 3, "completeness_actionability": 3},
        },
        "evidence": {"response": {"evidence_grounding": {"A": 1, "B": 3}, "claims": []}},
    }


class ConsensusTests(unittest.TestCase):
    def test_unanimous_docs_win_is_high_confidence(self) -> None:
        result = ANALYZER.consensus([judgment("B"), judgment("B"), judgment("B")])
        self.assertEqual("docs_win", result["outcome"])
        self.assertEqual("C1", result["winning_arm"])
        self.assertEqual("high", result["confidence"])
        self.assertFalse(result["human_review_required"])

    def test_two_of_three_is_medium_confidence(self) -> None:
        result = ANALYZER.consensus([judgment("B"), judgment("B"), judgment("A")])
        self.assertEqual("docs_win", result["outcome"])
        self.assertEqual("medium", result["confidence"])

    def test_split_with_unsure_is_inconclusive(self) -> None:
        result = ANALYZER.consensus([judgment("A"), judgment("B"), judgment("unsure")])
        self.assertEqual("inconclusive", result["outcome"])
        self.assertTrue(result["human_review_required"])

    def test_material_error_requires_human_review(self) -> None:
        result = ANALYZER.consensus(
            [judgment("B"), judgment("B", errors=[{"claim": "bad"}]), judgment("B")]
        )
        self.assertEqual("inconclusive", result["outcome"])
        self.assertTrue(result["human_review_required"])

    def test_scores_are_deblinded(self) -> None:
        scores = ANALYZER.deblinded_scores([judgment("B")])
        self.assertEqual(1.0, scores["C0"]["correctness"])
        self.assertEqual(3.0, scores["C1"]["correctness"])
        self.assertEqual(3.0, scores["C1"]["evidence_grounding"])


class ConsumptionTests(unittest.TestCase):
    def test_missing_metrics_are_unavailable(self) -> None:
        runs = [
            {"arm": "C0", "consumption": {}},
            {"arm": "C1", "consumption": {}},
        ]
        result = ANALYZER.compare_consumption(runs, "C0", "C1")
        self.assertEqual("unavailable", result["input_tokens"]["status"])
        self.assertIsNone(result["input_tokens"]["delta"])

    def test_measured_metrics_produce_delta(self) -> None:
        runs = [
            {"arm": "C0", "consumption": {"input_tokens": {"value": 100, "status": "measured"}}},
            {"arm": "C1", "consumption": {"input_tokens": {"value": 70, "status": "measured"}}},
        ]
        result = ANALYZER.compare_consumption(runs, "C0", "C1")
        self.assertEqual("measured", result["input_tokens"]["status"])
        self.assertEqual(-30.0, result["input_tokens"]["delta"])


class ContextTests(unittest.TestCase):
    def test_legacy_manifest_is_bounded_app_local(self) -> None:
        result = ANALYZER.context_summary({})
        self.assertEqual("app-local", result["profile"])
        self.assertEqual("unknown", result["adequacy"])
        self.assertTrue(result["bounded_case_study"])

    def test_dependency_source_manifest_is_not_bounded(self) -> None:
        result = ANALYZER.context_summary(
            {
                "context": {
                    "profile": "dependency-source",
                    "adequacy": "sufficient",
                    "dependency_paths": [{"path": "dependency"}],
                }
            }
        )
        self.assertEqual("dependency-source", result["profile"])
        self.assertEqual("sufficient", result["adequacy"])
        self.assertFalse(result["bounded_case_study"])
        self.assertEqual([{"path": "dependency"}], result["dependency_paths"])


if __name__ == "__main__":
    unittest.main()