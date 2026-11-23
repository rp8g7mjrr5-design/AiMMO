"""Sets the step output code=true unless every changed file is docs-only.

Docs-only: anything under docs/ or changelog.d/, or a Markdown file at the repo root
(CHANGELOG.md, README.md, CLAUDE.md). When in doubt (first push, API error, huge diff) it
says code=true, so the full test suite runs.
"""
import json
import os
import re
import subprocess
import sys

DOCS_ONLY = re.compile(r"^(docs/|changelog\.d/|[^/]+\.md$)")


def gh(path):
    out = subprocess.run(["gh", "api", "--paginate", path], capture_output=True, text=True, check=True).stdout
    # --paginate concatenates JSON arrays/objects; split them back up.
    dec, i, items = json.JSONDecoder(), 0, []
    while i < len(out):
        while i < len(out) and out[i].isspace():
            i += 1
        if i >= len(out):
            break
        obj, i = dec.raw_decode(out, i)
        items.append(obj)
    return items


def changed_files():
    repo, event = os.environ["GITHUB_REPOSITORY"], os.environ.get("EVENT", "")
    if event == "pull_request":
        pages = gh(f"repos/{repo}/pulls/{os.environ['PR']}/files?per_page=100")
        files = [f["filename"] for page in pages for f in page]
        return files if len(files) < 3000 else None
    if event == "push":
        before, sha = os.environ.get("BEFORE", ""), os.environ["GITHUB_SHA"]
        if not before or set(before) == {"0"}:
            return None
        cmp = gh(f"repos/{repo}/compare/{before}...{sha}")[0]
        files = cmp.get("files") or []
        if len(files) >= 300:  # the compare API stops listing at 300
            return None
        return [f["filename"] for f in files] + [f.get("previous_filename") for f in files if f.get("previous_filename")]
    return None  # workflow_dispatch: run everything


def main():
    try:
        files = changed_files()
    except Exception as e:  # noqa: BLE001 - any failure means "test everything"
        print(f"could not list changed files ({e}); running every test")
        files = None
    if files is None:
        code = True
    else:
        code = not files or any(not DOCS_ONLY.match(f) for f in files)
        print("changed files:\n  " + "\n  ".join(files) if files else "no changed files")
    print(f"code={'true' if code else 'false'} ({'full tests' if code else 'docs only: unit tests, no bot or smoke tests'})")
    with open(os.environ["GITHUB_OUTPUT"], "a") as out:
        out.write(f"code={'true' if code else 'false'}\n")


if __name__ == "__main__":
    sys.exit(main())
