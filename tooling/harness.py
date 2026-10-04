#!/usr/bin/env python3
"""Offline development checks; never signs, uploads, or modifies agent settings."""

import argparse
import ast
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
SKILLS = ("returnqueue-workflow", "returnqueue-swift-ios", "returnqueue-gitlab-release")
GUIDES = (
    "development-harness.md", "ios-architecture.md", "swift-style-guide.md",
    "gitlab-ci.md", "release-setup.md",
)


def run(command):
    subprocess.run(command, cwd=ROOT, check=True)


def unique_ids(text, pattern, label):
    values = re.findall(pattern, text, re.MULTILINE)
    if not values or len(values) != len(set(values)):
        raise ValueError(f"Missing or duplicate {label}")
    return set(values)


def check():
    feature = ROOT / "specs/001-free-return-prototype"
    spec = (feature / "spec.md").read_text()
    tasks = (feature / "tasks.md").read_text()
    requirements = unique_ids(spec, r"^- \*\*(FR-\d+)", "requirement IDs")
    stories = unique_ids(spec, r"^### User Story (\d+)", "story IDs")
    task_ids = unique_ids(tasks, r"^- \[[ xX]\] (T\d+)", "task IDs")
    for story in re.findall(r"\[US(\d+)\]", tasks):
        if story not in stories:
            raise ValueError(f"Task references unknown story US{story}")
    for reference in re.findall(r"\bFR-\d+\b", tasks):
        if reference not in requirements:
            raise ValueError(f"Task references unknown requirement {reference}")
    for name in ("plan.md", "data-model.md", "contracts/ui.md", "contracts/backup.md",
                 "contracts/storage.md", "contracts/presentation.md"):
        if not (feature / name).is_file():
            raise ValueError(f"Missing feature contract: {name}")
    json.loads((ROOT / ".swift-format").read_text())
    pages = [ROOT / "docs" / name for name in GUIDES]
    for name in SKILLS:
        path = ROOT / ".agents/skills" / name / "SKILL.md"
        content = path.read_text()
        if not content.startswith(f"---\nname: {name}\ndescription: "):
            raise ValueError(f"Invalid skill manifest: {name}")
        if "\n---\n" not in content[4:] or "TODO" in content:
            raise ValueError(f"Unfinished skill: {name}")
        pages.append(path)
    # Only maintained harness guides: planned source paths remain prose, not links.
    for page in pages:
        content = page.read_text()
        for target in re.findall(r"\[[^\]]*\]\(([^\s)]+)\)", content):
            if "://" in target or target.startswith(("#", "mailto:")):
                continue
            local = unquote(target.split("#", 1)[0]).strip("<>")
            if not (page.parent / local).exists():
                raise ValueError(f"Broken local link in {page.name}: {target}")
    for name in (".gitlab-ci.yml", "tooling/ci/check-core.sh", "tooling/ci/quality.sh",
                 "tooling/ci/archive-ios.sh", "tooling/ci/upload-testflight.sh",
                 "tooling/ci/release-common.sh", "tooling/ci/profile-options.py",
                 "tooling/ci/decode-file.py", "tooling/ci/test-release-tools.py"):
        if not (ROOT / name).is_file():
            raise ValueError(f"Missing CI foundation: {name}")
    for script in sorted((ROOT / "tooling/ci").glob("*.py")):
        ast.parse(script.read_text(), filename=str(script))
    for script in sorted((ROOT / "tooling/ci").glob("*.sh")):
        run(["bash", "-n", str(script)])
    run(["git", "diff", "--check"])
    print(f"Foundation OK: {len(requirements)} requirements, {len(stories)} stories, "
          f"{len(task_ids)} tasks; guides, skills and shell syntax checked.", flush=True)
    print("This is a structure check, not product acceptance or GitLab CI lint.", flush=True)


def doctor():
    for command in (["swift", "--version"], ["swift", "format", "--version"],
                    ["xcodebuild", "-version"]):
        print(f"Checking {' '.join(command)}", flush=True)
        if shutil.which(command[0]):
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            print((result.stdout + result.stderr).strip(), flush=True)
            print(f"Exit status: {result.returncode}", flush=True)
        else:
            print("Unavailable", flush=True)
    print(f"Xcode project present: {(ROOT / 'ReturnQueue.xcodeproj').exists()}")
    print("Diagnostics only; use verify for Core checks and configured CI for iOS.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("doctor", "check", "verify"))
    args = parser.parse_args()
    try:
        if args.command == "doctor":
            doctor()
        else:
            check()
            if args.command == "verify":
                run([sys.executable, "tooling/ci/test-release-tools.py"])
                run(["bash", "tooling/ci/quality.sh"])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Harness failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
