from pathlib import Path
import json
import sys


def argument_value(name: str) -> str:
    try:
        return sys.argv[sys.argv.index(name) + 1]
    except (ValueError, IndexError):
        return ""


def extract_answer(prompt: str, label: str, next_label: str | None) -> str:
    prompt = prompt.replace("\r\n", "\n")
    marker = f"Answer {label}:\n"
    if marker not in prompt:
        return ""
    value = prompt.split(marker, 1)[1]
    if next_label:
        value = value.split(f"\n\nAnswer {next_label}:\n", 1)[0]
    return value


def documented_answer_label(prompt: str) -> str:
    answer_a = extract_answer(prompt, "A", "B")
    answer_b = extract_answer(prompt, "B", None)
    if "Closed reviews are not reused" in answer_a:
        return "A"
    if "Closed reviews are not reused" in answer_b:
        return "B"
    return "unsure"


def main() -> int:
    required_arguments = {"--silent", "--no-color", "--no-ask-user"}
    if not required_arguments.issubset(sys.argv) or argument_value("--stream") != "off":
        print("Fake Copilot requires script-safe output arguments.", file=sys.stderr)
        return 2

    try:
        workspace = Path(sys.argv[sys.argv.index("-C") + 1])
    except (ValueError, IndexError):
        print("Fake Copilot requires -C <workspace>.", file=sys.stderr)
        return 2

    prompt = argument_value("-p")
    if "Return JSON only with 0-to-3 scores" in prompt:
        winner = documented_answer_label(prompt)
        loser = "B" if winner == "A" else "A"
        scores = {
            winner: {
                "correctness": 3,
                "completeness_actionability": 3,
                "scope_fit": 3,
                "uncertainty_safety": 3,
            },
            loser: {
                "correctness": 1,
                "completeness_actionability": 1,
                "scope_fit": 2,
                "uncertainty_safety": 2,
            },
        }
        print(
            "```json\n"
            + json.dumps(
                {
                    "scores": scores,
                    "dimension_winners": {
                        "correctness": winner,
                        "completeness_actionability": winner,
                        "scope_fit": winner,
                        "uncertainty_safety": winner,
                    },
                    "overall_winner": winner,
                    "confidence": "high",
                    "reason": "The selected answer states the synthetic policy explicitly.",
                }
            )
            + "\n```"
        )
        return 0

    if "Verify the critical claims" in prompt:
        winner = documented_answer_label(prompt)
        loser = "B" if winner == "A" else "A"
        print(
            "```json\n"
            + json.dumps(
                {
                    "claims": [
                        {
                            "answer": winner,
                            "claim": "Closed reviews are not reused.",
                            "status": "verified",
                            "evidence": "AGENTS.md and ReviewManagement.Codeunit.al",
                            "material_error": False,
                        },
                        {
                            "answer": loser,
                            "claim": "The exact policy is not explicit.",
                            "status": "unsupported",
                            "evidence": "The frozen documentation states the policy.",
                            "material_error": False,
                        },
                    ],
                    "evidence_grounding": {winner: 3, loser: 1},
                    "material_errors": [],
                }
            )
            + "\n```"
        )
        return 0

    documentation = workspace / "tools/bc-ai-knowledge-eval/examples/sample-app/AGENTS.md"
    if documentation.is_file():
        print(
            "The sample app reuses an open review for the same source document and "
            "creates a new review otherwise. Closed reviews are not reused. Evidence: "
            "AGENTS.md and src/ReviewManagement.Codeunit.al."
        )
    else:
        print(
            "The sample app appears to create or reuse a review based on "
            "ReviewManagement.Codeunit.al. The exact closed-review policy is not explicit in code."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())