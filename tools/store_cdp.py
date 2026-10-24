"""Fill the Garmin Connect IQ developer upload form from the command line.

Garmin has no upload API, so this drives a separate Edge window over the
DevTools protocol. You sign in to Garmin in that window yourself; the script
only reads and fills the form. Start the window with (PowerShell):

  Start-Process "${env:ProgramFiles(x86)}\\Microsoft\\Edge\\Application\\msedge.exe" `
    -ArgumentList "--remote-debugging-port=9333", "--user-data-dir=$env:USERPROFILE\\.garmin\\store-browser", `
    "https://apps.garmin.com/developer/upload"

Then: uv run --with playwright python -I tools/store_cdp.py <command> ...

  state                         URL, title and form controls (label / selector / type)
  text                          visible page text
  eval <js>                     run a JS function in the page, print the JSON result
  upload <file.iq>              set the app package (by path, so > 50 MB works)
  files <selector> <i> <f...>   set the i-th matching file input
  addshots <f...>               add store screenshots one at a time
  fill <selector> <text>        fill a field
  fillfile <selector> <file>    fill a field with a text file's content
  select <selector> <label>     choose an option
  click <selector> [seconds]    click and wait for the network to settle

Notes from the first submission (2026-10-24):
  - the description must not contain emoji (warning signs, triangles): keep it ASCII
  - "Signature check failed" on a first upload is a known store bug (CIQQA-4716); submitting works
  - country checkboxes mean "available in"; all are ticked by default
"""

import json
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

CDP_URL = "http://127.0.0.1:9333"

DUMP_JS = """
() => {
  const label = el => {
    if (el.labels && el.labels.length) return el.labels[0].innerText.trim();
    const l = el.closest('label'); if (l) return l.innerText.trim();
    return (el.getAttribute('aria-label') || el.placeholder || '').trim();
  };
  const sel = el => el.id ? '#' + CSS.escape(el.id) : (el.name ? `${el.tagName.toLowerCase()}[name="${el.name}"]` : null);
  return [...document.querySelectorAll('input, textarea, select, button')]
    .filter(el => el.type !== 'hidden')
    .map(el => ({tag: el.tagName.toLowerCase(), type: el.type, sel: sel(el), label: label(el).slice(0, 80),
                 text: (el.innerText || el.value || '').trim().slice(0, 60), visible: !!el.offsetParent}));
}
"""

# Index of the file input that adds another screenshot ("Add Image(s)")
ADD_SHOT_JS = """() => [...document.querySelectorAll('input[type=file]')].map((f, i) => {
  let e = f, label = '';
  for (let k = 0; k < 8 && e; k++) { e = e.parentElement; const t = (e && e.innerText || '').trim(); if (t.length > 5) { label = t; break; } }
  return label.startsWith('Add Image') ? i : -1; }).filter(i => i >= 0)"""


def set_files(page, selector: str, index: int, files: list[str]) -> None:
    """Give the browser local paths so it reads the files itself (Playwright
    refuses to stream files over 50 MB through a CDP connection)."""
    cdp = page.context.new_cdp_session(page)
    root = cdp.send("DOM.getDocument", {"depth": -1, "pierce": True})["root"]["nodeId"]
    node = cdp.send("DOM.querySelectorAll", {"nodeId": root, "selector": selector})["nodeIds"][index]
    cdp.send("DOM.setFileInputFiles", {"files": [str(Path(f).resolve()) for f in files], "nodeId": node})
    page.wait_for_timeout(4000)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    cmd, args = sys.argv[1], sys.argv[2:]
    with sync_playwright() as pw:
        browser = pw.chromium.connect_over_cdp(CDP_URL)
        pages = [p for c in browser.contexts for p in c.pages]
        page = ([p for p in pages if "garmin.com" in p.url] or pages)[-1]
        if cmd == "state":
            print(json.dumps({"url": page.url, "title": page.title()}, ensure_ascii=False))
            for control in page.evaluate(DUMP_JS):
                print(json.dumps(control, ensure_ascii=False))
        elif cmd == "text":
            print(page.inner_text("body"))
        elif cmd == "eval":
            print(json.dumps(page.evaluate(args[0]), ensure_ascii=False, indent=1))
        elif cmd == "upload":
            set_files(page, "input[type=file]", 0, args)
        elif cmd == "files":
            set_files(page, args[0], int(args[1]), args[2:])
        elif cmd == "addshots":
            for path in args:
                set_files(page, "input[type=file]", page.evaluate(ADD_SHOT_JS)[-1], [path])
                print("added", Path(path).name)
        elif cmd == "fill":
            page.fill(args[0], args[1])
        elif cmd == "fillfile":
            page.fill(args[0], Path(args[1]).read_text(encoding="utf-8"))
        elif cmd == "select":
            page.select_option(args[0], label=args[1])
        elif cmd == "click":
            page.click(args[0])
            try:
                page.wait_for_load_state("networkidle", timeout=float(args[1]) * 1000 if args[1:] else 15000)
            except Exception:
                print("still loading")
        print("url:", page.url)


if __name__ == "__main__":
    main()
