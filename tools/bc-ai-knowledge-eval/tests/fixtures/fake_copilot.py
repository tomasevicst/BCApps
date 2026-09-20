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
    if "Return exactly these 14 lines" in prompt:
        winner = documented_answer_label(prompt)
        loser = "B" if winner == "A" else "A"
        for answer, score in ((winner, 3), (loser, 1)):
            for dimension in ("correctness", "completeness_actionability", "scope_fit", "uncertainty_safety"):
                print(f"SCORE|{answer}|{dimension}|{score}")
        for dimension in ("correctness", "completeness_actionability", "scope_fit", "uncertainty_safety"):
            print(f"WINNER|{dimension}|{winner}")
        print(f"OVERALL|{winner}")
        print("CONFIDENCE|high")
        return 0

    if "Start with exactly two grounding lines" in prompt:
        winner = documented_answer_label(prompt)
        loser = "B" if winner == "A" else "A"
        print(f"GROUNDING|{winner}|3")
        print(f"GROUNDING|{loser}|1")
        print(f"CLAIM|{winner}|verified|false|AGENTS.md;src/ReviewManagement.Codeunit.al|Closed reviews are not reused.")
        print(f"CLAIM|{loser}|unsupported|false|AGENTS.md|The exact policy is not explicit.")
        return 0

    if "Return JSON only with 0-to-3 scores" in prompt:
        print('{"scores": invalid}')
        return 0

    if "Verify the critical claims" in prompt:
        print('{"claims": invalid}')
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