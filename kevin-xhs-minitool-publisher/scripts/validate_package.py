from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath

DEFAULT_MAX_BYTES = 10 * 1024 * 1024
TEXT_SUFFIXES = {".html", ".htm", ".js", ".mjs", ".cjs", ".css", ".json", ".svg", ".txt"}
ALLOWED_SUFFIXES = {
    ".html",
    ".htm",
    ".css",
    ".js",
    ".mjs",
    ".cjs",
    ".json",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".svg",
    ".woff",
    ".woff2",
    ".mp3",
    ".wav",
    ".ogg",
    ".mp4",
    ".webm",
    ".txt",
}
ALLOWED_NAMESPACE_URLS = {
    "http://www.w3.org/1999/xhtml",
    "http://www.w3.org/1999/xlink",
    "http://www.w3.org/2000/svg",
    "http://www.w3.org/1998/Math/MathML",
    "http://www.w3.org/XML/1998/namespace",
}

FORBIDDEN_JS = (
    ("network.fetch", r"\bfetch\s*\("),
    ("network.xhr", r"\bXMLHttpRequest\b"),
    ("network.websocket", r"\b(?:new\s+)?WebSocket\s*\("),
    ("network.sse", r"\b(?:new\s+)?EventSource\s*\("),
    ("network.webrtc", r"\b(?:new\s+)?RTCPeerConnection\s*\("),
    ("worker", r"\b(?:new\s+)?(?:SharedWorker|Worker)\s*\("),
    ("service-worker", r"\bnavigator\.serviceWorker\b"),
    ("wasm", r"\bWebAssembly\b"),
    ("dynamic.eval", r"\beval\s*\("),
    ("dynamic.function", r"\bnew\s+Function\s*\("),
    ("clipboard", r"\bnavigator\.clipboard\b|\bexecCommand\s*\(\s*['\"](?:copy|cut|paste)"),
    ("external.window-open", r"\bwindow\.open\s*\("),
    ("external.blank-target", r"\btarget\s*[:=]\s*[\x22\x27\x60]_blank[\x22\x27\x60]"),
    ("fullscreen", r"\brequestFullscreen\s*\("),
    ("geolocation", r"\bnavigator\.geolocation\b"),
    ("device-api", r"\bnavigator\.(?:bluetooth|usb|hid|serial|credentials|locks)\b"),
    ("download", r"\.[Dd]ownload\s*=|\bcreateObjectURL\s*\("),
)


@dataclass
class Finding:
    level: str
    code: str
    file: str
    message: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="校验小红书 Builder Hub 离线小工具包")
    parser.add_argument("path", type=Path, help="ZIP 文件或构建目录")
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=DEFAULT_MAX_BYTES,
        help="上传页当前显示的包体上限，默认 10MB",
    )
    return parser.parse_args()


def normalized_name(name: str) -> str:
    return name.replace("\\", "/").lstrip("./")


def read_input(path: Path) -> tuple[dict[str, bytes], int, list[Finding]]:
    findings: list[Finding] = []
    files: dict[str, bytes] = {}

    if path.is_file() and path.suffix.lower() == ".zip":
        archive_size = path.stat().st_size
        try:
            with zipfile.ZipFile(path) as archive:
                bad = archive.testzip()
                if bad:
                    findings.append(Finding("error", "zip.corrupt", bad, "ZIP 完整性校验失败"))
                seen: set[str] = set()
                for info in archive.infolist():
                    if info.is_dir():
                        continue
                    name = normalized_name(info.filename)
                    if name in seen:
                        findings.append(Finding("error", "zip.duplicate", name, "ZIP 内存在重复路径"))
                    seen.add(name)
                    files[name] = archive.read(info)
        except zipfile.BadZipFile:
            findings.append(Finding("error", "zip.invalid", str(path), "文件不是有效 ZIP"))
        return files, archive_size, findings

    if path.is_dir():
        total = 0
        for item in path.rglob("*"):
            if not item.is_file():
                continue
            name = item.relative_to(path).as_posix()
            data = item.read_bytes()
            files[name] = data
            total += len(data)
        return files, total, findings

    findings.append(Finding("error", "input.missing", str(path), "输入必须是 ZIP 或构建目录"))
    return files, 0, findings


def safe_member(name: str) -> bool:
    path = PurePosixPath(name)
    return not path.is_absolute() and ".." not in path.parts and not re.match(r"^[A-Za-z]:", name)


def decode_text(data: bytes) -> str:
    return data.decode("utf-8", errors="replace")


def scan(files: dict[str, bytes], size: int, max_bytes: int, seed: list[Finding]) -> list[Finding]:
    findings = list(seed)

    if size > max_bytes:
        findings.append(
            Finding("error", "size.limit", "<package>", f"包体 {size} bytes 超过当前上限 {max_bytes} bytes")
        )
    if "index.html" not in files:
        findings.append(Finding("error", "root.index", "<package>", "ZIP 根目录缺少 index.html"))

    for name, data in files.items():
        if not safe_member(name):
            findings.append(Finding("error", "path.unsafe", name, "ZIP 路径包含绝对路径或上级目录"))
            continue

        suffix = Path(name).suffix.lower()
        if suffix not in ALLOWED_SUFFIXES:
            findings.append(Finding("error", "file.unsupported", name, f"不支持的文件类型 {suffix or '<none>'}"))
        if suffix == ".map":
            findings.append(Finding("error", "file.sourcemap", name, "生产包不能包含 sourcemap"))
        if suffix not in TEXT_SUFFIXES:
            continue

        text = decode_text(data)
        urls = set(re.findall(r"https?://[^\s'\"<>`\\)]+", text, flags=re.IGNORECASE))
        external = sorted(url for url in urls if url.rstrip("/") not in ALLOWED_NAMESPACE_URLS)
        if external:
            sample = ", ".join(external[:3])
            more = "" if len(external) <= 3 else f"，另有 {len(external) - 3} 个"
            findings.append(
                Finding("error", "external.url", name, f"发现站外或远程 URL：{sample}{more}")
            )

        if suffix in {".html", ".htm"}:
            html_checks = (
                ("html.inline-script", r"<script\b(?![^>]*\bsrc\s*=)[^>]*>", "存在内联 script"),
                ("html.inline-event", r"\son[a-z]+\s*=", "存在行内事件处理器"),
                ("html.javascript-url", r"javascript\s*:", "存在 javascript: URL"),
                ("html.base", r"<base\b", "存在 base 标签"),
                ("html.iframe", r"<iframe\b", "存在 iframe"),
                ("html.blank-target", r"target\s*=\s*['\"]_blank['\"]", "存在 target=\"_blank\""),
                ("html.download", r"<a\b[^>]*\bdownload(?:\s|=|>)", "存在下载链接"),
                ("html.absolute-asset", r"\b(?:src|href)\s*=\s*['\"]/", "资源路径从站点根开始，不是 ./ 相对路径"),
            )
            for code, pattern, message in html_checks:
                if re.search(pattern, text, flags=re.IGNORECASE):
                    findings.append(Finding("error", code, name, message))

        if suffix in {".js", ".mjs", ".cjs"}:
            for code, pattern in FORBIDDEN_JS:
                if re.search(pattern, text, flags=re.IGNORECASE):
                    findings.append(Finding("error", code, name, f"命中禁用运行时能力 {code}"))

    if files and size < 1024:
        findings.append(Finding("warning", "size.suspicious", "<package>", "包体小于 1KB，请确认不是空壳"))
    return findings


def main() -> int:
    args = parse_args()
    path = args.path.resolve()
    files, size, seed = read_input(path)
    findings = scan(files, size, args.max_bytes, seed)
    errors = sum(item.level == "error" for item in findings)
    warnings = sum(item.level == "warning" for item in findings)
    result = {
        "ok": errors == 0,
        "path": str(path),
        "bytes": size,
        "maxBytes": args.max_bytes,
        "fileCount": len(files),
        "errors": errors,
        "warnings": warnings,
        "findings": [asdict(item) for item in findings],
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
