import tempfile
import unittest
from pathlib import Path

from validate_docs import (
    bare_al_filename_errors,
    boundary_errors,
    markdown_files,
    relative_link_errors,
    volatile_count_warnings,
)


class ValidateDocsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_directory = tempfile.TemporaryDirectory()
        self.scope = Path(self.temp_directory.name)
        self.source_root = self.scope / "src"

    def tearDown(self) -> None:
        self.temp_directory.cleanup()

    def write(self, relative_path: str, content: str) -> Path:
        path = self.scope / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def test_valid_documentation_passes_hard_checks(self) -> None:
        self.write("src/Area/Worker.Codeunit.al", "codeunit 1 Worker {}")
        self.write(
            "AGENTS.md",
            "# App\n\n| Folder | Decision |\n|---|---|\n| "
            "[`src/Area`](./src/Area) | document |\n\n"
            "[`Worker.Codeunit.al`](./src/Area/Worker.Codeunit.al) owns the behavior.\n",
        )

        files = markdown_files(self.scope)
        checked, link_errors = relative_link_errors(files)

        self.assertEqual(2, checked)
        self.assertEqual([], link_errors)
        self.assertEqual([], bare_al_filename_errors(files))
        self.assertEqual([], boundary_errors(self.scope, self.source_root))
        self.assertEqual([], volatile_count_warnings(files))

    def test_detects_broken_link_bare_filename_and_missing_boundary(self) -> None:
        self.write("src/Area/Worker.Codeunit.al", "codeunit 1 Worker {}")
        self.write("src/Missing/Other.Codeunit.al", "codeunit 2 Other {}")
        self.write(
            "AGENTS.md",
            "# App\n\n[`src/Area`](./src/Area) contains `Worker.Codeunit.al`. "
            "See [missing](./missing.md).\n",
        )

        files = markdown_files(self.scope)
        _, link_errors = relative_link_errors(files)

        self.assertEqual(1, len(link_errors))
        self.assertEqual(1, len(bare_al_filename_errors(files)))
        self.assertEqual(1, len(boundary_errors(self.scope, self.source_root)))

    def test_reports_volatile_implementation_counts(self) -> None:
        self.write("AGENTS.md", "The test app contains 30 test codeunits and approximately 8 helper codeunits.\n")

        warnings = volatile_count_warnings(markdown_files(self.scope))

        self.assertEqual(2, len(warnings))


if __name__ == "__main__":
    unittest.main()