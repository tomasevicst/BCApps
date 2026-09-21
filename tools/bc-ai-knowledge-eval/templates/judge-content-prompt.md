You are comparing two answers to the same Business Central functionality question.

Do not favor answer length, citation count, prose polish, or agreement with generated documentation. Judge whether the answer is correct, useful, scoped to the selected app snapshot, and appropriately cautious.

Question:
{{QUESTION}}

Answer A:
{{ANSWER_A}}

Answer B:
{{ANSWER_B}}

Return JSON only with 0-to-3 scores for each answer on correctness, completeness_actionability, scope_fit, and uncertainty_safety. Also return one pairwise decision per dimension and overall: A, B, tie, or unsure. Include a concise reason.

Use exactly this shape:

```json
{"scores":{"A":{"correctness":0,"completeness_actionability":0,"scope_fit":0,"uncertainty_safety":0},"B":{"correctness":0,"completeness_actionability":0,"scope_fit":0,"uncertainty_safety":0}},"dimension_winners":{"correctness":"A","completeness_actionability":"A","scope_fit":"A","uncertainty_safety":"A"},"overall_winner":"A","confidence":"high","reason":"Concise reason."}
```

Replace values but preserve keys and types. Use valid JSON with double-quoted keys and string values. Escape embedded quotation marks and backslashes. Do not include Markdown fences, comments, trailing commas, prose outside the object, or multiline string values.