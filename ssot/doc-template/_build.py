#!/usr/bin/env python3
"""스펙 문서 빌드: <문서>.src.html -> <문서>.html

src.html 은 AI 가 읽는 원문(근거가 주장 옆에 인라인), html 은 사람이 읽는 판이다.

하는 일:
1. img src="assets/..." 와 CSS url('assets/...') 를 base64 data URI 로 인라인
   (소스 파일 폴더에서 먼저 찾고, 없으면 이 템플릿 폴더의 assets/ 에서 찾는다).
   .ttf/.otf 는 문서 사용 글리프로 서브셋해 woff2 로 인라인한다
   (목업 폰트를 src 에 base64 로 박지 않는다. 템플릿 assets/fonts/ 에 두고 url() 로 참조).
2. fonts/manifest.json 의 폰트를 문서 사용 글리프로 서브셋(fonttools) 후
   @font-face 블록을 /*__FONTS__*/ 자리에 주입 (폰트는 항상 템플릿 폴더 기준)
3. 각주: 본문의 <span class="fn">근거</span> 를 문서 순서로 번호 매겨 <sup> 마커로 바꾸고,
   모은 목록을 <!--__FOOTNOTES__--> 자리에 <ol class="fnlist"> 로 넣는다.
   각주 안에는 span 을 쓰지 않는다 (code·b·i·a 만).
4. 외부 URL 참조가 남아 있으면 실패

사용: 프로젝트 어디서든
  python3 ssot/doc-template/_build.py notes/<유닛>/<유닛>.src.html

요구: python3 + fonttools + brotli (없으면
  uv run --with fonttools --with brotli python3 _build.py <src>)
"""
from __future__ import annotations
import base64
import io
import json
import re
import sys
from pathlib import Path

TPL = Path(__file__).resolve().parent
FONTS_DIR = TPL / "fonts"
MANIFEST = FONTS_DIR / "manifest.json"

MIME = {
    ".png": "image/png",
    ".webp": "image/webp",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".woff2": "font/woff2",
}
SUBSET_FONT_EXT = {".ttf", ".otf"}

if len(sys.argv) < 2:
    sys.exit("[build] FAIL: 소스 경로 필요. python3 _build.py <문서>.src.html")
_src_arg = sys.argv[1]
if not _src_arg.endswith(".src.html"):
    sys.exit(f"[build] FAIL: 소스는 *.src.html 이어야 함: {_src_arg}")
SRC = Path(_src_arg).resolve()
OUT = SRC.with_name(SRC.name.replace(".src.html", ".html"))

# 서브셋 안전 버퍼: 문서에 없어도 항상 포함할 글리프 (각주 마커 ↩ 포함)
BUFFER = (
    "0123456789"
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    "%×→←↑↓#Pp↩"
)

FN_RE = re.compile(r'<span class="fn">(.*?)</span>', re.S)
FOOTNOTES_MARK = "<!--__FOOTNOTES__-->"


def die(msg: str) -> None:
    print(f"[build] FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def subset_font(path: Path, text: str) -> bytes:
    from fontTools import subset

    opts = subset.Options()
    opts.flavor = "woff2"
    opts.desubroutinize = True
    opts.hinting = False
    opts.layout_features = ["*"]  # 합자과 커닝 유지
    opts.name_IDs = [1, 2]
    font = subset.load_font(str(path), opts)
    subsetter = subset.Subsetter(opts)
    subsetter.populate(text=text)
    subsetter.subset(font)
    buf = io.BytesIO()
    font.save(buf)
    return buf.getvalue()


def to_data_uri(rel: str, used_text: str) -> str:
    for base in (SRC.parent, TPL):
        p = base / rel
        if p.exists():
            ext = p.suffix.lower()
            if ext in SUBSET_FONT_EXT:
                data = subset_font(p, used_text + BUFFER)
                print(f"[build] 에셋 폰트 {rel}: {p.stat().st_size//1024}KB -> {len(data)//1024}KB (서브셋 woff2)")
                return f"data:font/woff2;base64,{base64.b64encode(data).decode()}"
            mime = MIME.get(ext)
            if not mime:
                die(f"지원 안 하는 에셋 형식: {rel}")
            b64 = base64.b64encode(p.read_bytes()).decode()
            return f"data:{mime};base64,{b64}"
    die(f"에셋 없음: {rel} (소스 폴더에도 템플릿 assets/ 에도 없음)")


def inline_assets(html: str, used_text: str) -> str:
    html = re.sub(
        r'src="(assets/[^"]+)"',
        lambda m: f'src="{to_data_uri(m.group(1), used_text)}"',
        html,
    )
    html = re.sub(
        r"url\(['\"]?(assets/[^'\")]+)['\"]?\)",
        lambda m: f"url('{to_data_uri(m.group(1), used_text)}')",
        html,
    )
    return html


def build_fonts(used_text: str) -> str:
    if not MANIFEST.exists():
        die("fonts/manifest.json 없음")
    manifest = json.loads(MANIFEST.read_text())
    css_parts: list[str] = []
    total = 0
    for set_key, roles in manifest["sets"].items():
        for role, info in roles.items():
            family = info["family"]
            # 라틴 전용 폰트는 작은 텍스트로 충분하다
            text = BUFFER if info.get("latin_only") else used_text + BUFFER
            for weight, fname in info["files"].items():
                p = FONTS_DIR / "src" / fname
                if not p.exists():
                    die(f"폰트 파일 없음: {fname}")
                data = subset_font(p, text)
                total += len(data)
                b64 = base64.b64encode(data).decode()
                css_parts.append(
                    "@font-face{font-family:'%s';font-weight:%s;font-style:normal;"
                    "font-display:block;src:url(data:font/woff2;base64,%s) format('woff2');}"
                    % (family, weight, b64)
                )
                print(f"[build] {set_key}/{role} {family} {weight}: {len(data)//1024}KB")
    print(f"[build] 폰트 합계: {total//1024}KB")
    return "\n".join(css_parts)


def build_footnotes(html: str) -> str:
    """<span class="fn">…</span> -> <sup> 마커 + 최하단 목록. 번호는 문서 순서."""
    notes: list[str] = []

    def rep(m: re.Match) -> str:
        body = m.group(1).strip()
        if "<span" in body:
            die(f"각주 안에 span 금지 (code·b·i·a 만): {body[:80]}")
        n = len(notes) + 1
        notes.append(body)
        return f'<sup class="fn" id="fnr-{n}"><a href="#fn-{n}" data-fn="{n}">{n}</a></sup>'

    # <script> 안의 문자열은 건드리지 않는다 (목업 JS 가 같은 클래스명을 쓸 수 있다 · king-face 선례)
    parts = re.split(r"(<script\b.*?</script>)", html, flags=re.S)
    html = "".join(p if p.startswith("<script") else FN_RE.sub(rep, p) for p in parts)
    if FOOTNOTES_MARK not in html:
        if notes:
            die(f"각주 {len(notes)}건이 있는데 {FOOTNOTES_MARK} 자리가 없음")
        return html
    if notes:
        items = "\n".join(
            f'    <li id="fn-{i}"><span class="n">{i}</span><span class="t">{t}</span>'
            f'<a class="back" href="#fnr-{i}" title="본문으로">↩</a></li>'
            for i, t in enumerate(notes, 1)
        )
        block = f'<ol class="fnlist" id="fnlist">\n{items}\n  </ol>'
    else:
        block = '<p class="note">각주 없음.</p>'
    print(f"[build] 각주 {len(notes)}건")
    return html.replace(FOOTNOTES_MARK, block)


def main() -> None:
    if not SRC.exists():
        die(f"소스 없음: {SRC}")
    html = SRC.read_text(encoding="utf-8")
    if "data:font/" in html:
        print(
            "[build] WARN: src 에 폰트 base64 직접 삽입 (레거시 문서). 새 문서는 템플릿 assets/fonts/ 에 두고 "
            "url('assets/fonts/…') 로 참조한다",
            file=sys.stderr,
        )

    used_chars = "".join(sorted(set(re.sub(r"<[^>]+>", "", html))))
    html = inline_assets(html, used_chars)
    html = build_footnotes(html)

    font_css = build_fonts(used_chars)
    if "/*__FONTS__*/" not in html:
        die("/*__FONTS__*/ 플레이스홀더 없음")
    html = html.replace("/*__FONTS__*/", font_css)

    leftovers = re.findall(r'(?:src|href)="https?://[^"]+"', html)
    if leftovers:
        die(f"외부 URL 잔존: {leftovers[:3]}")

    OUT.write_text(html, encoding="utf-8")
    print(f"[build] OK -> {OUT} {OUT.stat().st_size//1024}KB")


if __name__ == "__main__":
    main()
