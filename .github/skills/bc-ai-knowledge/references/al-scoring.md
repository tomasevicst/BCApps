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

For child folders:

1. Walk from the deepest folders toward the requested root.
2. Ignore folders with fewer than three owned AL objects unless they contain a declared namespace boundary or a substantial object that cannot be understood from its parent.
3. Score a folder using files directly below it and descendant files not already assigned to an accepted child boundary.
4. Once a child boundary is accepted, its detailed evidence belongs to the child. The parent receives only a responsibility summary and link.
5. Do not propose documentation for a chain of ancestors that would describe the same evidence.

For namespace scope, score exact namespace matches within the selected app root as one logical area after resolving its physical owner. Supporting files inside that app root contribute evidence but do not create another namespace document. Do not aggregate layers or independent apps.

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
