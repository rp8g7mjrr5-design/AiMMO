"""Fast checks on Dockerfile that need no Docker: run with
python3 -m unittest discover -s tests/ops -p 'test_*.py'

The slow, real check is run_image_test.py against a built image; these catch the common
mistakes (a renamed file, a new script not copied in) in under a second on any machine.
"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_image_test  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DOCKERFILE = (REPO / "Dockerfile").read_text()
IGNORED = [l.strip() for l in (REPO / ".dockerignore").read_text().splitlines() if l.strip()]


def copy_sources() -> list:
    out = []
    for line in DOCKERFILE.splitlines():
        m = re.match(r"^COPY\s+(.+)$", line.strip())
        if m:
            parts = [p for p in m.group(1).split() if not p.startswith("--")]
            out += parts[:-1]
    return out


class DockerfileTest(unittest.TestCase):
    def test_every_copy_source_exists(self):
        sources = copy_sources()
        self.assertTrue(sources, "Dockerfile has no COPY lines")
        for src in sources:
            self.assertTrue((REPO / src).exists(), f"Dockerfile copies {src}, which is not in the repo")

    def test_no_copy_source_is_dockerignored(self):
        for src in copy_sources():
            top = src.rstrip("/").split("/")[0]
            self.assertNotIn(top, [i.rstrip("/") for i in IGNORED],
                             f"Dockerfile copies {src} but .dockerignore leaves it out of the build context")

    def test_every_docker_script_is_copied(self):
        copied = set(copy_sources())
        for script in sorted((REPO / "docker").glob("*.sh")):
            rel = f"docker/{script.name}"
            self.assertIn(rel, copied, f"{rel} exists but the Dockerfile never copies it into the image")

    def test_image_test_checks_every_copied_script(self):
        for script in sorted((REPO / "docker").glob("*.sh")):
            self.assertIn(f"/app/{script.name}", run_image_test.REQUIRED_FILES,
                          f"run_image_test.py does not check /app/{script.name} is in the image")

    def test_default_cmd_is_the_entrypoint(self):
        self.assertIn('CMD ["/app/entrypoint.sh"]', DOCKERFILE)

    def test_image_test_env_matches_dockerfile(self):
        for k, v in run_image_test.REQUIRED_ENV.items():
            self.assertRegex(DOCKERFILE, rf"\b{k}={re.escape(v)}\b", f"Dockerfile no longer sets {k}={v}")


if __name__ == "__main__":
    unittest.main()
