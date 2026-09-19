# Initialize BC AL documentation

Bootstrap human-first documentation for one AL app, folder, or exact namespace. Discovery and planning are read-only. Do not create or edit files before the user approves the documentation map.

## Preflight

1. Read:
   - [Scope resolution](./references/scope-resolution.md)
   - [AL documentation scoring](./references/al-scoring.md)
   - [Writing standard](./references/writing-standard.md)
2. Resolve the requested target to an app root, logical scope, and physical documentation owner.
   - If app-root or physical ownership is ambiguous, present the candidates, ask the user to choose, and stop before Phase 1.
3. Load repository instructions that apply to the proposed Markdown locations.
4. Confirm the scope contains AL source. Stop if the target is empty, generated output, or not an AL area.
5. Inventory local, parent, and accepted child documentation before proposing files, including legacy `CLAUDE.md` content.
6. If useful local documentation already exists or legacy orientation needs migration, route to [update](./update.md).

## Phase 1: Read-only discovery

Use parallel read-only investigations when the environment supports them. Give every investigator the resolved scope, physical owner, exclusions, and existing documentation. Keep searches bounded to the app and directly related test or dependency areas.

### Structure and ownership

Determine:

- App metadata and source roots from `app.json` and repository structure.
- AL objects grouped by declaration type, physical folder, and exact namespace.
- Parent, child, and neighboring responsibilities.
- App dependencies that materially affect the local mental model.
- Existing documentation and candidate child boundaries.
- Namespace declaration files and supporting locations outside a namespace owner.

Apply the scoring reference bottom-up. Return evidence and recommendations, not an object inventory for publication.

### Data model

Read the tables, table extensions, enums, and related procedures needed to explain the domain model. Identify:

- Conceptual entities and why they are separate.
- Primary relationships and cardinalities.
- Lifecycle, consistency, and deletion rules.
- Non-obvious fields only when their purpose affects behavior.
- Boundaries owned by another area that should be linked rather than copied.

### Business behavior and extensibility

Read complete relevant procedures for a small number of important flows. Identify:

- User or system entry points.
- Validation, decisions, state changes, delegation, errors, and final outcomes.
- Events, subscribers, interfaces, extension objects, and replacement patterns.
- Local patterns and legacy approaches that should not be copied.
- Cross-area calls that require a link or explicit boundary statement.

Do not attempt repository-wide end-to-end process reconstruction.

### Tests and existing knowledge

Use bounded searches based on the scoped objects, procedures, namespace, and app dependencies. Read selected tests in full and return:

- Business setup, action, and meaningful assertion.
- Important scenarios demonstrated by source.
- Material behavior without located coverage.
- Contradictions between test source, implementation, and existing documentation.
- Human-written rationale or decisions that must be preserved.

Do not return a complete test inventory. Do not claim test execution.

### Optional official documentation

When the `microsoft.docs.mcp` server is available:

1. Use `microsoft_docs_search` for the app or feature area, important business operations, and official Business Central terminology.
2. Use `microsoft_docs_fetch` to read the most relevant pages in full before using them as evidence.
3. Use `microsoft_code_sample_search` only when an official sample clarifies an extension or integration pattern relevant to the selected scope.
4. Record the page title and URL for every Learn source that materially affects the documentation map or generated prose.
5. Keep research bounded to the selected AL area. Do not turn app documentation into a summary of Microsoft Learn.

When the server or a tool is unavailable, continue with source-only discovery and report the limitation. Current source establishes observed implementation behavior. Microsoft Learn establishes published terminology and product guidance. Record meaningful conflicts as unresolved rather than silently choosing a rationale.

## Phase 2: Documentation map

Synthesize discovery into one proposed map. Include all `MUST_DOCUMENT` and `SHOULD_DOCUMENT` candidates, but explain when overlap makes a separate file unnecessary.

Use this structure:

```markdown
## Documentation map

### Resolved scope

| Field | Value |
|-------|-------|
| Requested target | ... |
| Scope kind | app, folder, or namespace |
| App root | ... |
| Physical owner | ... |
| Supporting locations | ... |

### Candidate boundaries

| Boundary | Score | Classification | Decision | Reason |
|----------|-------|----------------|----------|--------|
| ... | ... | ... | document, link, or omit | ... |

### Files

| File | Action | Scope and purpose | Evidence | Links | Exclusions |
|------|--------|-------------------|----------|-------|------------|
| ... | create or update | ... | ... | ... | ... |

### Intentionally omitted

| File or scope | Reason |
|---------------|--------|
| ... | ... |

### Questions requiring review

- ...
```

For every proposed file, state why it earns its existence. `AGENTS.md` is required for an approved scope. Every focused file is conditional.

For namespace scope, show the selected app root, dominant physical owner, supporting locations inside that app, and exact file counts. Ownership ambiguity must already be resolved during preflight.

## Phase 3: Approval gate

Present the map and ask the user to approve or revise it. Stop until explicit approval is received.

Approval authorizes the proposed file operations and observed-behavior content. It does not turn unsupported rationale into approved intent. Keep unsupported intent unresolved.

## Phase 4: Generate documentation

After approval:

1. Re-read each existing target file in full immediately before editing.
2. Generate non-overlapping scopes in parallel only when agents cannot edit the same files.
3. Preserve valid human prose and existing links.
4. Use the approved physical locations:
   - App orientation: `<app-root>/AGENTS.md`
   - App focused files: `<app-root>/docs/<category>.md`
   - Folder or namespace orientation: `<physical-owner>/AGENTS.md`
   - Folder or namespace focused files: `<physical-owner>/docs/<category>.md`
5. Keep category files flat within `docs/`. Respect existing user-created subdirectories but do not create new category subdirectories.
6. Use relative Markdown links with `/` separators.
7. Keep app and parent files concise. Link to child detail rather than repeating it.
8. Keep scoring counts and object inventories in the documentation map only. Do not copy them into `AGENTS.md` or focused documentation.
9. Follow the writing standard for authority, tests, diagrams, and excluded content.

## Phase 5: Validate

Validate the generated set before reporting completion:

- Read from both the parent entry point and local `AGENTS.md` as a developer new to the area.
- Verify every relative link and referenced source path.
- Verify each focused file matches evidence and has one clear purpose.
- Check that parent, child, folder, and namespace scopes do not duplicate detailed content.
- Confirm namespace docs live under the approved physical owner and link supporting locations.
- Check that selected tests are explained by scenario and no execution claim was invented.
- Search for object, field, procedure, event, and test inventories that should be prose instead.
- Check applicable Markdown instructions and whitespace.
- Review the final diff and confirm only approved documentation files changed.

## Completion report

Report:

- Resolved scope and physical owner.
- Files created or updated.
- Child boundaries linked or intentionally omitted.
- Source and selected tests reviewed.
- Microsoft Learn sources used, or confirmation that Learn enrichment was unavailable or unnecessary.
- Observed behavior, approved intent sources, and unresolved questions.
- Validation results and checks that could not run.
