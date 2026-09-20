Verify critical claims in both answers against the workspace source, tests, official Microsoft Learn guidance, and frozen documentation. Generated documentation is navigation evidence, not final authority.

Question:
{{QUESTION}}

Answer A:
{{ANSWER_A}}

Answer B:
{{ANSWER_B}}

Return line protocol only. Do not use JSON, Markdown, comments, extra prose, tabs, or pipe characters inside values.

Start with exactly two grounding lines, using integer scores from 0 to 3:

GROUNDING|A|0
GROUNDING|B|0

Then return one CLAIM line per critical claim using this shape:

CLAIM|A|verified|false|relative/path/File.al;relative/path/Test.al|Concise claim without pipe characters

The answer is A or B. Status is verified, unsupported, contradicted, or unresolved. Material error is true or false. Use repository-relative paths with forward slashes, separated by semicolons. Return at least one claim for each answer.