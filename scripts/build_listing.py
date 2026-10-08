#!/usr/bin/env python3
"""Sestaví webovou stránku se všemi texty a snímky pro App Store Connect.

Použití:
  scripts/build_listing.py                      -> appstore/listing.html (obrázky odkazem na appstore/screenshots)
  scripts/build_listing.py --embed OUT.html     -> samostatná stránka s vloženými náhledy (pro publikaci jako artefakt)
Texty se čtou z appstore/metadata/<jazyk>/*.txt, takže stránka je vždy shodná s tím, co testují AppStoreMetadataTests.
"""
import base64, html, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
META = ROOT / "appstore" / "metadata"
SHOTS = ROOT / "appstore" / "screenshots"
WEB = ROOT / "docs" / "web" / "img"
SITE = "https://ok1xoe.github.io/TCommander/"

LIMITS = {"name": 30, "subtitle": 30, "promotional_text": 170, "description": 4000, "keywords": 100, "release_notes": 4000}
FIELDS = [("name", "Name"), ("subtitle", "Subtitle"), ("promotional_text", "Promotional Text"),
          ("description", "Description"), ("keywords", "Keywords"), ("release_notes", "What’s New in This Version")]
LOCALES = [("en-US", "English (U.S.)", "primary"), ("cs", "Czech", "additional")]

SHOT_TITLES = {
    "01-two-panels": "Two panels with tabs, thumbnails and marked files",
    "02-syntax-highlighting": "Viewer with syntax highlighting",
    "03-markdown-reader": "Markdown rendered as a page",
    "04-compare-files": "Side-by-side file comparison",
    "05-synchronize": "Folder synchronization with a preview",
    "06-find-files": "Search by name and content",
    "07-multi-rename": "Multi-Rename with live preview",
    "08-terminal": "Built-in terminal running vim",
}
REVIEW_NOTE = ("TCommander is a file manager. Because of the App Sandbox it asks once, at first launch, for a folder it may use "
               "(please choose your home folder in the dialog). It remembers the choice using security-scoped bookmarks. You can also "
               "drop a folder on the app icon. All features are available without sign-in. Network features (FTP/FTPS/SMB/WebDAV) work "
               "with any server you enter; no server is needed to review the app. SFTP, plugins and PlantUML rendering are intentionally "
               "disabled in this edition because they require running other programs.")

esc = html.escape
n_copy = 0

def field(label, value, limit=None, mono=False, hint=""):
    global n_copy
    n_copy += 1
    i = f"f{n_copy}"
    count = ""
    if limit:
        n = len(value)
        cls = "ok" if n <= limit else "over"
        count = f'<span class="count {cls}">{n} / {limit}</span>'
    h = f'<p class="hint">{esc(hint)}</p>' if hint else ""
    return (f'<div class="field"><div class="fhead"><label for="{i}">{esc(label)}</label>{count}'
            f'<button type="button" class="copy" data-for="{i}">Copy</button></div>{h}'
            f'<textarea id="{i}" readonly rows="{min(14, max(1, value.count(chr(10)) + 1 + len(value)//90))}"'
            f'{" class=mono" if mono else ""}>{esc(value)}</textarea></div>')

def img_src(name, embed):
    if embed:
        p = WEB / f"screenshot-{name}.jpg"
        return "data:image/jpeg;base64," + base64.b64encode(p.read_bytes()).decode()
    return f"screenshots/{name}.png"

def build(embed):
    parts = []
    # 1. Záznam aplikace
    app = [("Bundle ID", "cz.ok1xoe.TCommander", None), ("SKU", "tcommander-mac", None), ("Platform", "macOS", None),
           ("Primary language", "English (U.S.)", None), ("Primary category", "Utilities", None), ("Secondary category", "Productivity", None),
           ("Copyright", "2026 Tomáš Kaplan", None), ("Version", "1.0.0", None), ("Price", "Tier for USD 1.99 (or your own choice)", None)]
    urls = [("Support URL", "https://github.com/ok1xoe/TCommander/issues"), ("Marketing URL", SITE),
            ("Privacy Policy URL (English)", SITE + "docs/en/privacy.html"), ("Privacy Policy URL (Czech)", SITE + "docs/cs/privacy.html")]
    parts.append('<section id="app"><h2>App record</h2><p class="lead">Fields to fill in when you create the app and its first version in App Store Connect.</p><div class="grid2">'
                 + "".join(field(l, v) for l, v, _ in app) + "</div><h3>Links</h3><div class=\"grid2\">"
                 + "".join(field(l, v) for l, v in urls) + "</div></section>")
    # 2. Texty podle jazyků
    for code, name, kind in LOCALES:
        d = META / code
        blocks = []
        for key, label in FIELDS:
            v = (d / f"{key}.txt").read_text(encoding="utf-8").strip()
            blocks.append(field(label, v, LIMITS[key], hint="Not shown on the product page, used for search only." if key == "keywords" else ""))
        parts.append(f'<section id="loc-{code}"><h2>{esc(name)}</h2><p class="lead">{"Primary language of the app record." if kind == "primary" else "Add this under Languages in the version, then fill in the same fields."}</p>'
                     + "".join(blocks) + "</section>")
    # 3. Snímky
    figs = []
    for p in sorted(SHOTS.glob("*.png")):
        name = p.stem
        cap = SHOT_TITLES.get(name, name)
        figs.append(f'<figure><img src="{img_src(name, embed)}" alt="{esc(cap)}" loading="lazy" width="1600" height="1000">'
                    f'<figcaption><b>{esc(p.name)}</b><span>{esc(cap)}</span><span class="mono">2880 × 1800 px</span></figcaption></figure>')
    parts.append('<section id="shots"><h2>Screenshots</h2><p class="lead">macOS accepts 1280×800, 1440×900, 2560×1600 and 2880×1800 (16:10), up to 10 images. '
                 'These are 2880×1800, in English, taken from the demo data. Upload them in this order to the 2880×1800 slot.'
                 + ("" if not embed else " The previews below are reduced; the full-size PNG files are in <code>appstore/screenshots/</code> in the repository.")
                 + f'</p><div class="shots">{"".join(figs)}</div></section>')
    # 4. Review, soukromí, věk, export
    answers = [("App Privacy", "Data Not Collected"), ("Sign-in required", "No (no demo account needed)"),
               ("Age rating", "Answer None / No to every question. Result: 4+"),
               ("Export compliance", "The app uses only encryption provided by the operating system (TLS, hashing): exempt. Info.plist already sets ITSAppUsesNonExemptEncryption to NO."),
               ("Content rights", "The app contains no third-party content."),
               ("Advertising identifier", "Not used")]
    parts.append('<section id="review"><h2>Review and compliance</h2><p class="lead">Answers for the questionnaires and the note to the reviewer.</p>'
                 + field("Notes for App Review", REVIEW_NOTE, 4000)
                 + '<h3>Questionnaires</h3><dl class="qa">' + "".join(f"<dt>{esc(k)}</dt><dd>{esc(v)}</dd>" for k, v in answers) + "</dl>"
                 + '<h3>Contact information</h3><p class="lead">First name, last name, phone and email for App Review are yours to enter. They are not stored in this repository.</p></section>')
    parts.append('<section id="risk"><h2>Before you submit</h2><ul class="check">'
                 '<li><b>Name.</b> “TCommander” resembles Total Commander, which is a trademark. App Review can reject the name under guideline 5.2. Check the trademark first, and have a second name ready (the name field takes 30 characters).</li>'
                 '<li><b>Provisioning profile.</b> Create the App ID and a Mac App Store Connect profile for <code>cz.ok1xoe.TCommander</code>, then run <code>PROVISIONING_PROFILE=… scripts/appstore.sh</code> and upload the .pkg with Transporter.</li>'
                 '<li><b>Edition differences.</b> SFTP, plugins and PlantUML are off in the sandboxed edition. The description and keywords do not mention them.</li>'
                 '<li><b>Web page link.</b> After approval, set the repository variable <code>APPSTORE_URL</code> so the website links to the store.</li></ul></section>')
    nav = ('<nav aria-label="Sections"><a href="#app">App record</a><a href="#loc-en-US">English (U.S.)</a><a href="#loc-cs">Czech</a>'
           '<a href="#shots">Screenshots</a><a href="#review">Review</a><a href="#risk">Before you submit</a></nav>')
    head = ('<header><p class="eyebrow">Mac App Store · version 1.0.0</p><h1>TCommander App Store Kit</h1>'
            '<p class="lead">Every text, link and screenshot for App Store Connect. Counters show the length against Apple’s limit; Copy puts the text on the clipboard.</p></header>')
    return head + '<div class="layout">' + nav + "<main>" + "".join(parts) + "</main></div>"

CSS = """
:root{--bg:#f4f6f8;--panel:#ffffff;--fg:#1b2430;--muted:#5c6877;--line:#d9dfe6;--accent:#0b6b64;--accent-fg:#ffffff;--over:#b3261e;--code:#eef1f4}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#12171d;--panel:#1a2129;--fg:#e6ebf0;--muted:#9aa7b5;--line:#2c3541;--accent:#4cc3b8;--accent-fg:#0a1513;--over:#ff8a80;--code:#222b35;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#12171d;--panel:#1a2129;--fg:#e6ebf0;--muted:#9aa7b5;--line:#2c3541;--accent:#4cc3b8;--accent-fg:#0a1513;--over:#ff8a80;--code:#222b35;color-scheme:dark}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--fg);font:15px/1.55 "IBM Plex Sans",system-ui,-apple-system,"Segoe UI",sans-serif;margin:0;padding-inline:16px;padding-block:28px 64px}
.mono,code,textarea.mono{font-family:"IBM Plex Mono",ui-monospace,Menlo,monospace}
header,.layout{max-width:1120px;margin-inline:auto}
header{padding-bottom:20px}
.eyebrow{margin:0 0 6px;font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--accent);font-weight:600}
h1{font-size:clamp(28px,5vw,40px);line-height:1.1;margin:0 0 10px;text-wrap:balance;font-weight:700}
h2{font-size:22px;margin:0 0 4px;text-wrap:balance}
h3{font-size:13px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);margin:26px 0 10px}
.lead{color:var(--muted);margin:0 0 18px;max-width:68ch}
.layout{display:grid;grid-template-columns:190px minmax(0,1fr);gap:32px;align-items:start}
nav{position:sticky;top:env(safe-area-inset-top,0px);padding-top:6px;display:flex;flex-direction:column;gap:2px}
nav a{color:var(--muted);text-decoration:none;padding:6px 10px;border-left:2px solid var(--line);font-size:14px}
nav a:hover,nav a:focus-visible{color:var(--fg);border-left-color:var(--accent);outline:none}
main{min-width:0;display:flex;flex-direction:column;gap:28px}
section{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:22px;scroll-margin-top:16px;min-width:0}
.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px}
.field{display:flex;flex-direction:column;gap:6px;margin-bottom:16px;min-width:0}
.grid2 .field{margin-bottom:0}
.fhead{display:flex;align-items:center;gap:10px}
.fhead label{font-weight:600;font-size:14px;margin-right:auto}
.count{font-size:12px;font-variant-numeric:tabular-nums;color:var(--muted);font-family:"IBM Plex Mono",ui-monospace,monospace}
.count.over{color:var(--over);font-weight:700}
.hint{margin:0;font-size:13px;color:var(--muted)}
textarea{width:100%;resize:vertical;background:var(--code);color:var(--fg);border:1px solid var(--line);border-radius:6px;padding:9px 11px;font:inherit;font-size:14px;line-height:1.5}
textarea:focus{outline:2px solid var(--accent);outline-offset:1px}
.copy{font:inherit;font-size:13px;font-weight:600;background:var(--accent);color:var(--accent-fg);border:0;border-radius:6px;padding:5px 12px;cursor:pointer;min-width:64px}
.copy:focus-visible{outline:2px solid var(--fg);outline-offset:2px}
.copy.done{background:var(--muted)}
.shots{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:18px}
figure{margin:0;min-width:0}
figure img{display:block;width:100%;height:auto;aspect-ratio:16/10;object-fit:cover;border:1px solid var(--line);border-radius:6px;background:var(--code)}
figcaption{display:flex;flex-direction:column;gap:1px;margin-top:7px;font-size:13px}
figcaption span{color:var(--muted)}
.qa{display:grid;grid-template-columns:minmax(120px,200px) minmax(0,1fr);gap:8px 18px;margin:0}
.qa dt{font-weight:600}.qa dd{margin:0;color:var(--muted)}
.check{margin:0;padding-left:20px;display:flex;flex-direction:column;gap:10px}
code{background:var(--code);padding:1px 5px;border-radius:4px;font-size:13px;overflow-wrap:anywhere}
@media (max-width:760px){.layout{grid-template-columns:minmax(0,1fr)}nav{position:static;flex-direction:row;flex-wrap:wrap;gap:6px}nav a{border:1px solid var(--line);border-radius:999px}section{padding:16px}.qa{grid-template-columns:minmax(0,1fr)}}
@media (prefers-reduced-motion:no-preference){.copy{transition:background .15s}}
"""
JS = """
document.querySelectorAll('.copy').forEach(function(b){b.addEventListener('click',function(){
  var t=document.getElementById(b.dataset.for);
  function ok(){b.textContent='Copied';b.classList.add('done');setTimeout(function(){b.textContent='Copy';b.classList.remove('done')},1400)}
  function fallback(){t.focus();t.select();try{document.execCommand('copy')&&ok()}catch(e){}}
  if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t.value).then(ok,fallback)}else{fallback()}
})});
"""
FONTS = '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;600;700&display=swap">'

def main():
    embed = "--embed" in sys.argv
    body = build(embed)
    title = "TCommander App Store Kit"
    if embed:
        out = pathlib.Path(sys.argv[sys.argv.index("--embed") + 1])
        out.write_text(f"<title>{title}</title>\n{FONTS}\n<style>{CSS}</style>\n{body}\n<script>{JS}</script>\n", encoding="utf-8")
    else:
        out = ROOT / "appstore" / "listing.html"
        out.write_text(f'<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
                       f"<title>{title}</title>{FONTS}<style>{CSS}</style></head><body>{body}<script>{JS}</script></body></html>\n", encoding="utf-8")
    print("Hotovo:", out)

main()
