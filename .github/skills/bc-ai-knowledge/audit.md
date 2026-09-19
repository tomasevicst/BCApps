# Audit BC AL documentation

Assess documentation for one AL app, folder, or exact namespace. This workflow is strictly read-only. Do not create, edit, move, or delete files.

## Preflight

1. Read:
   - [Scope resolution](./references/scope-resolution.md)
   - [AL documentation scoring](./references/al-scoring.md)
   - [Writing standard](./references/writing-standard.md)
2. Resolve the requested scope and expected physical documentation owner.
3. Load repository instructions that apply to existing Markdown.
4. Record the initial working-tree status so read-only behavior can be verified at completion.

When namespace ownership is ambiguous, report the candidate owners and continue the audit without choosing or moving documentation.

## Step 1: Parallel inventory

Use parallel read-only investigations when available.

### Source and boundaries

- Inventory recognized AL declarations by folder and exact namespace.
- Read `app.json` and identify nested app exclusions.
- Recompute folder and namespace candidate scores bottom-up.
- Identify the expected parent, local, child, and supporting boundaries.

### Existing documentation

- Inventory the local `AGENTS.md`, any legacy `CLAUDE.md`, and flat Markdown files under `docs/`.
- Read parent and child entry points that establish navigation or ownership.
- Find non-standard, misplaced, duplicate, and orphaned documentation.
- Record linked source and test paths for validation.

### Content quality

- Check whether each document explains purpose, boundaries, behavior, relationships, extension surfaces, or gotchas.
- Identify mechanical object, field, procedure, event, or test inventories.
- Identify volatile exact or approximate counts of implementation elements that will drift without adding durable knowledge.
- Verify app dependency wording distinguishes explicit extension dependencies from application and platform targets.
- For interface-backed enums described as extension surfaces, verify the documented registration mechanism against `Extensible` and `Implementation` declarations.
- Separate supported intent, observed behavior, proposals, and unresolved questions.
- Find important claims without usable evidence links.

### Tests and freshness

- Use bounded searches for tests related to the documented scope.
- Compare selected test descriptions with setup, action, and assertions in source.
- Verify every selected scenario and Test Library helper links directly to its exact source file.
- Identify relevant source changes newer than the documentation using Git history when available.
- Treat newer source as a freshness risk, not proof that prose is wrong.
- Treat broken evidence links or contradicted claims as concrete defects.

## Step 2: Determine expected documentation

Use scoring and discovered evidence to determine the minimum useful set:

- `<app-root>/AGENTS.md` for app scope.
- `<physical-owner>/AGENTS.md` for folder or namespace scope.
- Focused files only when their evidence would add substantial knowledge.
- Child documentation for accepted `MUST_DOCUMENT` and `SHOULD_DOCUMENT` boundaries, unless overlap makes a link more appropriate.

Do not count empty placeholders or mechanical inventories as useful coverage.
An empty `docs` directory is context, not a finding status. Classify each justified missing file as `MISSING`.

## Step 3: Classify findings

Use these statuses consistently:

| Status | Meaning |
|--------|---------|
| `EXISTS` | Correctly placed and useful for its stated scope. |
| `MISSING` | Evidence justifies a document that does not exist. |
| `MISPLACED` | Useful content exists outside its real physical owner. |
| `OVERLAPPING` | Detailed content is duplicated across parent, child, folder, or namespace scopes. |
| `ORPHANED` | The documented scope or linked source no longer exists. |
| `BROKEN` | A relative link or evidence reference does not resolve. |
| `UNSUPPORTED` | A material claim lacks evidence or presents inferred intent as fact. |
| `POTENTIALLY_STALE` | Relevant source changed after the document and the affected subject needs review. |
| `NOT_REQUIRED` | Discovery does not justify this optional document for the current scope. |

One file can have more than one finding. Use only statuses from this table. Do not label content stale based only on age.

Classify a legacy app-root or `docs/CLAUDE.md` orientation file as `MISPLACED`. Recommend an approval-gated migration to the expected `AGENTS.md` path, preserving content and repairing relative links. When both files exist, flag overlapping orientation and recommend one merged `AGENTS.md`.

## Step 4: Score audit dimensions

Score each dimension from 0 to 3.

| Score | Meaning |
|-------|---------|
| 0 | Missing, misleading, or unsafe to rely on. |
| 1 | Major gaps require substantial correction. |
| 2 | Useful with focused improvements. |
| 3 | Clear, grounded, well-linked, and appropriate for scope. |

Score:

- Scope coverage.
- Physical placement and ownership.
- Progressive navigation.
- Human readability and signal.
- Source grounding and authority language.
- Selected test evidence.
- Freshness risk.

## Output

Return one report:

```markdown
# BC AL documentation audit

## Resolved scope

| Field | Value |
|-------|-------|
| Requested target | ... |
| Scope kind | ... |
| App root | ... |
| Expected physical owner | ... |
| Ownership ambiguity | ... |

## Scores

| Dimension | Score | Evidence |
|-----------|-------|----------|
| ... | 0 to 3 | ... |

## Findings

| Priority | Status | File or scope | Finding | Recommendation |
|----------|--------|---------------|---------|----------------|
| ... | ... | ... | ... | ... |

## Expected documentation

| File or boundary | Expected | Current status | Reason |
|------------------|----------|----------------|--------|
| ... | yes or no | ... | ... |

## Recommended next steps

1. ...
```

Order findings by correctness and misleading-content risk, then navigation and coverage, then polish.

Recommendations must follow the Docs Pattern. Do not recommend creating or updating `README.md`; use `AGENTS.md` for orientation. Do not recommend version, localization, partner-overlay, or cross-app documentation from this skill.

At completion, compare working-tree status with the initial snapshot and confirm that the audit made no changes.