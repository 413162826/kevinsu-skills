#!/usr/bin/env python3
"""Validate the minimal public contract of a Codex Skill."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml


def validate_skill(skill_path: Path) -> tuple[bool, str]:
    skill_md = skill_path / "SKILL.md"
    if not skill_md.is_file():
        return False, "SKILL.md not found"

    content = skill_md.read_text(encoding="utf-8")
    match = re.match(r"^---\r?\n(.*?)\r?\n---", content, re.DOTALL)
    if not match:
        return False, "Invalid YAML frontmatter"

    try:
        frontmatter = yaml.safe_load(match.group(1))
    except yaml.YAMLError as error:
        return False, f"Invalid YAML: {error}"
    if not isinstance(frontmatter, dict):
        return False, "Frontmatter must be a mapping"
    if set(frontmatter) != {"name", "description"}:
        return False, "Frontmatter must contain only name and description"

    name = frontmatter.get("name")
    description = frontmatter.get("description")
    if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name):
        return False, "name must use lowercase hyphen-case"
    if len(name) > 64 or name != skill_path.name:
        return False, "name must match the folder name and be at most 64 characters"
    if not isinstance(description, str) or not description.strip() or len(description) > 1024:
        return False, "description must contain 1-1024 characters"
    if "<" in description or ">" in description:
        return False, "description cannot contain angle brackets"

    return True, "Skill is valid!"


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: quick_validate.py <skill_directory>")
        return 2
    valid, message = validate_skill(Path(sys.argv[1]))
    print(message)
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
