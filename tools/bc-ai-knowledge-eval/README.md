# BC AI knowledge evaluation tool

Compare Copilot answers from code-only and docs-assisted snapshots of any documented AL app.

## Status

The tool is under active development. Current modes validate inputs, prepare isolated workspaces, export/import manual run packages, run Copilot CLI automatically, and generate deterministic reports from stored artifacts.

## Prerequisites

- PowerShell 7
- Git
- Authenticated GitHub Copilot CLI
- Python 3.11 or later for analysis and report generation

No Business Central container or AL build is required.

## Privacy

Keep real Teams questions, customer context, responses, logs, judgments, consumption data, and reports outside BCApps. The repository contains only schemas, templates, tests, and synthetic examples.

Always pass an external `output_root` in the evaluation config. The tool refuses an output path inside the repository.

By default, preparation exports the whole repository so Copilot can inspect related tests and dependencies. Set `workspace_paths` to repository-relative paths only when a deliberately narrower context is sufficient.

## Quick start

Copy the synthetic examples outside the repository and replace their values:

```powershell
$tool = '.\tools\bc-ai-knowledge-eval\Invoke-BcAiKnowledgeEval.ps1'

pwsh -NoProfile -File $tool -Mode dry-run -ConfigPath C:\private-evals\evaluation.json
pwsh -NoProfile -File $tool -Mode prepare -ConfigPath C:\private-evals\evaluation.json
pwsh -NoProfile -File $tool -Mode export-run-pack -ConfigPath C:\private-evals\evaluation.json
```

Invoke the entry point with `pwsh`, even when the current terminal is labeled PowerShell. Windows PowerShell 5.1 is not supported.

For automatic answer generation:

```powershell
pwsh -NoProfile -File $tool -Mode calibrate -ConfigPath C:\private-evals\evaluation.json -ConfirmPaidRuns
pwsh -NoProfile -File $tool -Mode run -ConfigPath C:\private-evals\evaluation.json -ConfirmPaidRuns
pwsh -NoProfile -File $tool -Mode judge -ConfigPath C:\private-evals\evaluation.json -ConfirmPaidRuns
pwsh -NoProfile -File $tool -Mode report -ConfigPath C:\private-evals\evaluation.json
```

Run these stages one at a time and continue only after the previous stage reports success. If `judge` reports any failure, stop immediately: do not run `report`, do not rerun with `-Force`, and do not delete completed answer artifacts. Diagnose and fix the judge invocation or output-parsing issue first, then rerun `judge` so resumable valid artifacts are preserved and paid calls are not repeated unnecessarily.

For a complete automatic flow after calibration:

```powershell
pwsh -NoProfile -File $tool -Mode all -ConfigPath C:\private-evals\evaluation.json -ConfirmPaidRuns
```

## Modes

| Mode | Purpose |
|------|---------|
| `dry-run` | Validate configuration, questions, models, app path, and docs manifest without creating workspaces. |
| `prepare` | Create Git-free code-only and docs-assisted workspaces and verify their byte manifests. |
| `calibrate` | Verify Copilot invocation and available consumption measurements using synthetic prompts. |
| `run` | Run pending answer arms automatically in fresh Copilot CLI processes. |
| `export-run-pack` | Write exact prompts and commands for manual answer execution. |
| `import-response` | Import a manually captured response into the canonical run schema. |
| `judge` | Run pending blind LLM judge comparisons automatically. |
| `export-judge-pack` | Export anonymized A/B comparisons for manual judging. |
| `import-judgment` | Import a manual or external judgment. |
| `report` | Regenerate reports from existing artifacts without model calls. |
| `all` | Run every automatable stage, pausing at approval or manual gates. |

## Evaluation conditions

- `C0`: selected answer model, code-only workspace
- `C1`: same answer model, docs-assisted workspace
- `E0` and `E1`: optional economical-model pair

The C0/C1 pair is always present. It isolates documentation value while holding the model constant.

## Hybrid operation

Automatic and manual artifacts share the same IDs and schemas. An evaluation can use automatic answers with manual judging, manual answers with automatic judging, or any other compatible combination.

All stages are resumable. Use `-Force` only when an existing valid artifact must be replaced.

Automatic answer runs start a fresh Copilot process for each question, arm, and repeat. By default only `view`, `grep`, and `glob` are available to the model. Configure `available_tools` only with additional read-only tools; every run is invalidated if its workspace hash changes.

## Output layout

```text
<output_root>/<evaluation_id>/
|-- evaluation-manifest.json
|-- workspaces/
|   |-- code-only/
|   `-- docs-assisted/
|-- workspace-manifests/
|-- run-packs/
|-- runs/
|-- judge-packs/
|-- judge-pass-runs/
|-- judge-pass-failures/
|-- judgments/
`-- reports/
```

Automatic judging caches valid content and evidence passes independently under `judge-pass-runs/`. If a pass returns malformed JSON, it is preserved under `judge-pass-failures/` and retried once with a delimiter-based response contract. Rerun `judge` without `-Force`; valid passes and complete judgments are reused while only missing or invalid work is retried.

## Limitations

- Copilot CLI token and credit telemetry varies by version. Metrics are reported as `measured`, `partial`, or `unavailable`.
- Calibration reads aggregate rows from the local Copilot CLI session store in read-only mode. It records no prompt, response, checkpoint, or command content.
- LLM judging is not accepted blindly. Contradictions, material errors, and low-confidence comparisons remain inconclusive until adjudicated.
- The tool evaluates the selected source snapshot. It does not infer behavior for other releases or localizations.
- CI and a Copilot skill wrapper are deferred until the local runner is stable.
