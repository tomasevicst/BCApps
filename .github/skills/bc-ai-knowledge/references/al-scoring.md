# AL documentation scoring

## Purpose

Scoring identifies candidate documentation boundaries and suggests which document types may provide value. It does not authorize file creation. Every proposed file must appear in an approved documentation map or update plan.

## Object detection

Identify AL object type from its declaration in source, not from its filename. Ignore comments and attributes before the declaration.

| Object family | Declarations |
|---------------|--------------|
| Data model | `table`, `tableextension`, `enum`, `enumextension` |
| Business logic | `codeunit`, `query`, `report`, `reportextension`, `xmlport` |
| User interface | `page`, `pageextension`, `pagecustomization`, `profile` |
| Extensibility | `interface`, extension objects, event publishers, event subscribers |
| Security and platform | `permissionset`, `permissionsetextension`, `entitlement`, `controladdin` |

Files that contain no recognized object declaration can still provide evidence, but they do not increase object counts.

## Candidate boundaries

The explicitly requested app, folder, or resolved namespace owner is always a candidate, even when its score is low.

### Boundary coverage ledger

For app and folder scopes, build a complete ledger before scoring:

1. List every immediate child folder that owns AL source recursively, excluding nested app roots.
2. Assign each child one decision: `document`, `link`, or `omit`.
3. Record its responsibility, owned namespaces, important dependencies, semantic-complexity signals, score, and decision reason.
4. Recursively evaluate descendants when a child contains multiple coherent responsibilities or namespaces, or when a descendant owns a semantic-complexity signal.
5. Stop recursion when a folder has one coherent responsibility and no descendant would provide more specific context.

Every immediate AL-owning child must appear in the documentation map, including omitted children. A directory's existence alone does not justify documentation, but no child may disappear from analysis merely because its parent was documented.

### Bottom-up ownership

For child folders:

1. Walk from the deepest folders toward the requested root.
2. Ignore folders with fewer than three owned AL objects unless they contain a declared namespace boundary or a substantial object that cannot be understood from its parent.
3. Score a folder using files directly below it and descendant files not already assigned to an accepted child boundary.
4. Once a child boundary is accepted, its detailed evidence belongs to the child. The parent receives only a responsibility summary and link.
5. Do not propose documentation for a chain of ancestors that would describe the same evidence.

A parent boundary can own several small related children when they share one mental model. Prefer the narrowest coherent owner, not the deepest possible folder and not one file set per directory.

For namespace scope, score exact namespace matches within the selected app root as one logical area after resolving its physical owner. Supporting files inside that app root contribute evidence but do not create another namespace document. Do not aggregate layers or independent apps.

## Semantic complexity

Object counts estimate navigation cost but do not measure design complexity. Mark a candidate with a semantic-complexity signal when bounded source and test reading finds one of these:

- A public interface, extensible enum, or strategy/registration contract whose implementations live across several objects or folders.
- Dynamic `RecordRef`, `RecordId`, `FieldRef`, or `Variant` traversal, recursive graph walking, configurable field mapping, expression parsing, or runtime dispatch.
- Rule ordering, precedence, fallback, propagation, or state-transition behavior that is not clear from declarations.
- Orchestration across transaction, posting, workflow, job queue, or background-session boundaries.
- Several event subscribers that together adapt one external business process and have local gating, filtering, error, or idempotency rules.
- Important invariants, failure modes, or ownership boundaries that a developer must know before changing the subtree.
- Selected tests that establish a distinct local behavioral contract not explained adequately by parent documentation.
- Existing parent documentation that tells readers to inspect a local implementation directly, or marks a local mechanism unresolved because its rules are too detailed for the parent.

Apply semantic complexity after the numeric score:

- One supported signal raises an `OPTIONAL` candidate to at least `SHOULD_DOCUMENT` review. Propose local `AGENTS.md` when the knowledge would materially reduce rediscovery; otherwise record a justified `link` decision.
- Two independent signals, or one central extension/algorithm contract with meaningful tests, raises the candidate to `MUST_DOCUMENT` review.
- A semantic override is not automatic file creation. The documentation map must still show why local context is better than extending the parent document.
- Do not use large file size, procedure count, namespace count, or event count alone as a semantic signal.

## Large-scope sanity gate

Treat a scope as large and multi-area when any of these are true:

- It owns at least 50 recognized AL objects.
- It has at least 5 immediate AL-owning child folders.
- It contains at least 3 coherent namespaces or responsibilities.

If discovery proposes no child documentation boundaries for such a scope:

1. Show the coverage-ledger decision for every immediate child.
2. Test representative maintenance tasks in the most complex children: identify which `AGENTS.md` Copilot CLI would load and whether it contains the needed local invariants, change risks, and test pointers.
3. Explain why parent documentation is sufficient for each semantic-complexity signal found.
4. Mark zero child boundaries as an unresolved documentation-map decision unless this evidence supports the omission.

## Score

Add applicable points and cap the result at 10.

| Factor | Points | Detection rule |
|--------|--------|----------------|
| At least 3 tables or table extensions | 3 | Count recognized declarations owned by the candidate. |
| At least 3 codeunits | 2 | Count recognized declarations owned by the candidate. |
| At least 3 interfaces | 3 | Count recognized declarations owned by the candidate. |
| Event publishers present | 1 | Find an actual `[IntegrationEvent]` or `[BusinessEvent]` attribute in owned source. Do not infer publication from names or calls. |
| Event subscribers present | 1 | Find an actual `[EventSubscriber]` attribute in owned source. Do not count subscribers from another app root. |
| At least 10 AL objects | 2 | Count recognized declarations owned by the candidate. |
| Substantive codeunit present | 1 | At least one codeunit contains 10 or more procedure declarations. |
| Extension objects present | 1 | Find a table, page, report, enum, or permission-set extension declaration. |
| Relevant tests found | 1 | Bounded discovery finds selected test procedures that exercise this area. |

## Classification

| Category | Score | Recommendation |
|----------|-------|----------------|
| `MUST_DOCUMENT` | 7 to 10 | Propose `AGENTS.md` and at least one evidence-backed focused file. |
| `SHOULD_DOCUMENT` | 4 to 6 | Propose `AGENTS.md`; add a focused file only when discovery justifies it. |
| `OPTIONAL` | 0 to 3 | Skip by default unless this is the explicitly requested scope or a reviewer identifies valuable knowledge. |

## Document selection

Select files from evidence, not score alone.

| Evidence | Candidate document |
|----------|--------------------|
| Tables, table extensions, enums, lifecycle relationships | `data-model.md` |
| Codeunits, reports, queries, XMLports, pages that orchestrate behavior | `business-logic.md` |
| Events, interfaces, extension objects, replacement or strategy patterns | `extensibility.md` |
| Selected tests with meaningful scenarios or gaps | `testing.md` |
| Non-obvious conventions or legacy approaches | `patterns.md` |

Do not create a focused file when it would contain only an object inventory.

## Update mapping

Use this table as an initial routing hint, then inspect semantic behavior before proposing an update.

| Changed declaration or behavior | Primary candidates |
|---------------------------------|--------------------|
| Table, table extension, enum, enum extension | `data-model.md` |
| Codeunit, report, query, XMLport | `business-logic.md` |
| Event publisher or subscriber | `business-logic.md`, `extensibility.md` |
| Interface or extension object | `extensibility.md`, sometimes `patterns.md` |
| Page or page extension | `AGENTS.md`; `business-logic.md` only when it orchestrates material behavior |
| Permission or entitlement | `AGENTS.md`; a focused file only when the security model needs explanation |
| Test setup, action, or assertion | `testing.md`; behavior docs when expected behavior changed |

The nearest owning document is updated first. Parent documents change only when their summary, navigation, or boundary statement became inaccurate.
