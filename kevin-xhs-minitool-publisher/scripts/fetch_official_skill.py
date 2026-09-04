#!/usr/bin/env python3
"""下载并安全解包 Builder Hub 当前页面提供的小工具官方 Skill。"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import stat
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath


MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024


def fail(message: str) -> None:
    raise ValueError(message)


def validate_url(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https":
        fail("官方 Skill 地址必须使用 HTTPS")
    if host != "xhscdn.com" and not host.endswith(".xhscdn.com"):
        fail(f"官方 Skill 地址不是小红书 CDN 域名：{host or '<empty>'}")
    if not parsed.path.endswith(".skill"):
        fail("下载地址不是 .skill 文件")


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "Codex-XHS-MiniTool-Audit/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        length = response.headers.get("Content-Length")
        if length and int(length) > MAX_DOWNLOAD_BYTES:
            fail("官方 Skill 包超过 20MB 安全上限")
        data = response.read(MAX_DOWNLOAD_BYTES + 1)
    if len(data) > MAX_DOWNLOAD_BYTES:
        fail("官方 Skill 包超过 20MB 安全上限")
    return data


def safe_member_path(name: str) -> PurePosixPath:
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    if path.is_absolute() or ".." in path.parts or any(":" in part for part in path.parts):
        fail(f"压缩包包含不安全路径：{name}")
    return path


def extract_skill(data: bytes, output_dir: Path) -> tuple[Path, list[Path]]:
    if output_dir.exists() and any(output_dir.iterdir()):
        fail(f"输出目录不是空目录：{output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    extracted: list[Path] = []
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        bad_file = archive.testzip()
        if bad_file:
            fail(f"官方 Skill 压缩包损坏：{bad_file}")
        for info in archive.infolist():
            relative = safe_member_path(info.filename)
            if not relative.parts:
                continue
            mode = (info.external_attr >> 16) & 0xFFFF
            if stat.S_ISLNK(mode):
                fail(f"压缩包包含符号链接：{info.filename}")
            target = output_dir.joinpath(*relative.parts)
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(info))
            extracted.append(target)

    skill_files = [path for path in extracted if path.name == "SKILL.md"]
    if len(skill_files) != 1:
        fail(f"官方包应包含且只包含一个 SKILL.md，实际为 {len(skill_files)}")
    return skill_files[0], extracted


def read_version(skill_path: Path) -> str:
    text = skill_path.read_text(encoding="utf-8")
    match = re.search(r'^\s*version:\s*["\']?([^"\'\r\n]+)', text, re.MULTILINE)
    return match.group(1).strip() if match else "unknown"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", help="从 Builder Hub 当前上传页口令提取的 .skill 地址")
    parser.add_argument("--output-dir", required=True, type=Path, help="唯一的空临时目录")
    args = parser.parse_args()

    try:
        validate_url(args.url)
        data = download(args.url)
        skill_path, extracted = extract_skill(data, args.output_dir.resolve())
        audit_scripts = [
            str(path.resolve())
            for path in extracted
            if path.name in {"audit_artifact.py", "audit_artifact.mjs"}
        ]
        result = {
            "ok": True,
            "url": args.url,
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "version": read_version(skill_path),
            "skillPath": str(skill_path.resolve()),
            "auditScripts": audit_scripts,
            "fileCount": len(extracted),
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
