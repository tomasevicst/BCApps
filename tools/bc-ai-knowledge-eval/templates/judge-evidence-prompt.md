Verify the critical claims in Answer A and Answer B against the current workspace source, tests, official Microsoft Learn guidance, and frozen documentation.

Generated documentation may help locate evidence but is not final authority.

Question:
{{QUESTION}}

Answer A:
{{ANSWER_A}}

Answer B:
{{ANSWER_B}}

For each critical claim, return: answer, claim, status (verified, unsupported, contradicted, or unresolved), evidence, and material_error (true or false). Score evidence grounding from 0 to 3 for each answer. Return JSON only.

Use exactly this shape:

```json
{"claims":[{"answer":"A","claim":"Concise claim.","status":"verified","evidence":["relative/path/File.al"],"material_error":false}],"evidence_grounding":{"A":0,"B":0},"material_errors":[]}
```

Replace values but preserve keys and types. Each evidence item must be a short string using repository-relative paths with forward slashes. Use valid JSON with double-quoted keys and string values. Escape embedded quotation marks and backslashes. Do not include Markdown fences, comments, trailing commas, prose outside the object, or multiline string values. Put each material error claim object in both `claims` and `material_errors`; otherwise leave `material_errors` empty.