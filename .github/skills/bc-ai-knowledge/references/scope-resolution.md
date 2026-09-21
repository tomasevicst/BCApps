# AL documentation scope resolution

## Purpose

Every mode resolves an app, folder, or exact namespace to one physical documentation owner before discovery or change analysis continues. Documentation stays beside real code. Never create a source directory from a namespace name.

## Accepted targets

Accept one of:

- A path to an AL app root or a directory inside an AL app.
- An exact namespace written as `namespace:Microsoft.Example.Area`.
- An exact namespace name when repository search finds one unambiguous match.

Accept `within:<app-path>` as an optional namespace boundary. The path must resolve to one app root and limits namespace matching to that app.

Ask for clarification when the target is missing, does not exist, matches several workspaces, or could mean both a path and a namespace.

Do not broaden an exact namespace to child namespaces. Do not broaden a folder request to the entire app unless the user approves that change.

## App scope

1. Confirm the target directory contains `app.json`, or locate the nearest ancestor `app.json` when the user identified an app directory below its root.
2. Read `app.json` as structured JSON and record name, publisher, dependencies, ID ranges, runtime, and source settings that affect discovery.
3. Identify source roots from the app structure instead of assuming a fixed `src` directory.
4. Exclude nested directories that contain another `app.json`; they are independent apps.
5. Discover related test apps only through explicit app dependencies, established sibling conventions, or direct test references. Do not scan every test app in the repository.
6. Use the app root as documentation owner. App orientation belongs in `<app-root>/AGENTS.md`; focused files belong in `<app-root>/docs/`.
7. Build a boundary coverage ledger for every immediate AL-owning source folder and recurse according to [AL documentation scoring](./al-scoring.md).

## Folder scope

1. Confirm the target contains AL source directly or below it.
2. Find the nearest ancestor app root for app metadata and parent context.
3. Include AL files below the requested folder, excluding nested app roots.
4. Discover child documentation candidates bottom-up using [AL documentation scoring](./al-scoring.md).
5. Use the requested folder as documentation owner. Its files belong in `<folder>/docs/`.
6. If the folder contains several unrelated namespaces or responsibilities, show that in the documentation map and propose coherent child boundaries rather than one catch-all document.
7. Record a `document`, `link`, or `omit` decision for every immediate AL-owning child before resolving the hierarchy.

## Namespace scope

### Match exact source

1. Parse top-level AL declarations in the form `namespace <dot.separated.name>;`, ignoring leading whitespace and comments. Compare the complete AL identifier without prefix matching, preserve the declared casing in output, and do not include child namespaces.
2. Partition matches by their nearest owning `app.json` before selecting a physical owner.
3. Select one app root from `within:<app-path>`, active-file context, or an unambiguous single-app result.
4. If matches occur under multiple app roots, layers, or independent apps and context does not select one, present the candidate app roots and counts, then ask the user which app to document.
5. Do not treat matches from other app roots or repository layers as supporting files. Version, localization, and cross-app comparison are outside this skill.
6. Within the selected app root, include files with no namespace only when a direct reference proves they participate in the requested area and label them as supporting evidence.
7. Group exact matches by their containing physical folders.
8. Record namespace declaration files, commonly named `*.Namespace.al`, as ownership evidence but not as conclusive proof by themselves.

### Select a physical owner

Choose a physical owner using this order:

1. A folder that contains the namespace declaration file and at least half of the exact namespace files.
2. Otherwise, the deepest coherent folder that contains at least 60 percent of exact matches and at least twice as many matches as the next independent folder.
3. Otherwise, a common parent only when the namespace is the clear responsibility of that parent and the parent will not mix unrelated areas into one document.
4. If none applies, present candidate folders, file counts, declaration-file locations, and neighboring namespaces, then ask the user to choose.

The selected owner contains namespace documentation under its real `docs` directory. Files in other locations are supporting locations linked from that documentation.

Supporting locations must remain inside the selected app root. References to dependencies outside the app may provide context, but they do not participate in namespace ownership or scoring.

### Prevent duplicate ownership

- When folder and namespace scopes resolve to the same owner and substantially the same AL files, propose one documentation set, not separate folder and namespace sets.
- When one folder owns several coherent namespaces, its `AGENTS.md` may orient across them while focused child documents retain distinct responsibilities.
- When a namespace spans several physical areas with different responsibilities, do not force one owner. Ask whether to document the physical areas separately.

## Existing documentation

For the resolved owner, inventory:

- Local `AGENTS.md` and flat Markdown files under `docs/`.
- Legacy app-root or `docs/CLAUDE.md` orientation content that may require migration.
- The nearest parent `AGENTS.md` and parent documentation needed for orientation.
- Accepted child documentation boundaries.
- Existing links from parent or neighboring documentation.

Preserve user-created documentation subdirectories if they already exist, but do not create new category subdirectories. Generated category files remain flat within the selected `docs` directory.

## Resolution result

Before a mode continues, record:

| Field | Meaning |
|-------|---------|
| Requested scope | Original app path, folder path, or exact namespace. |
| Scope kind | `app`, `folder`, or `namespace`. |
| App root | One selected owning app and `app.json`. |
| Physical owner | Directory where documentation will live. |
| Primary AL files | Files directly owned by the resolved scope. |
| Supporting locations | Relevant files outside the physical owner. |
| Child boundaries | Accepted or candidate child scopes that own detail. |
| Boundary coverage | Decision and reason for every immediate AL-owning child. |
| Existing docs | Local, parent, and child documentation that must be preserved or linked. |
| Ambiguities | Decisions that require user confirmation. |

Stop and ask the user when physical ownership remains ambiguous. Init and update must not propose writes before resolution is complete. Audit may report the ambiguity without resolving it.