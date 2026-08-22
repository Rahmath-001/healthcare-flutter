"""Prints docs/HANDBOOK.html to docs/MiDoctor-Handbook.pdf.

    python tool/make_handbook_pdf.py

Needs Chrome or Edge installed and a network connection for the fonts.

Two rewrites are made to a throwaway copy; the repository file is never
touched, so there is one source and nothing to drift.

1. `display=swap` becomes `display=block`. Swap is right for the web - text
   appears at once in a fallback and swaps when the real face lands - but for
   a one-shot headless print it is a race the fallback can win, and the PDF
   ships in Segoe UI.

2. The single multi-weight Google Fonts request is split into one request per
   weight. Asking for several weights of a family returns a *variable* font
   file, and Chrome's PDF backend cannot embed one: it silently substitutes,
   and the exported file then carries font names with no font programs, so it
   renders in whatever the reader's machine has. Asking for one weight at a
   time returns static instances, which embed. Verified by counting
   /FontFile entries in the descriptor dictionaries below - the check is the
   point, because nothing about the failure is visible on the generating
   machine.
"""
import io, os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace(os.sep, '/')
SRC = ROOT + '/docs/HANDBOOK.html'
OUT = ROOT + '/docs/MiDoctor-Handbook.pdf'
TMP = tempfile.mkdtemp(prefix='handbook-').replace(os.sep, '/') + '/handbook-print.html'

CANDIDATES = [
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
]
CHROME = next((c for c in CANDIDATES if os.path.exists(c)),
              shutil.which('google-chrome') or shutil.which('chromium'))
if not CHROME:
    sys.exit('No Chrome or Edge found. Install one, or open docs/HANDBOOK.html '
             'in a browser and print to PDF.')

# Every face the page uses, one request each.
FACES = [
    ('Newsreader', 'wght@400'),
    ('Newsreader', 'wght@500'),
    ('Newsreader', 'wght@600'),
    ('Newsreader', 'ital,wght@1,400'),
    ('IBM+Plex+Sans', 'wght@400'),
    ('IBM+Plex+Sans', 'wght@500'),
    ('IBM+Plex+Sans', 'wght@600'),
    ('IBM+Plex+Mono', 'wght@400'),
]

html = io.open(SRC, encoding='utf-8').read()
link = re.search(r'<link rel="stylesheet" href="https://fonts\.googleapis\.com[^"]+">', html)
assert link, 'no Google Fonts link in the source'

replacement = chr(10).join(
    '<link rel="stylesheet" href="https://fonts.googleapis.com/css2'
    '?family=%s:%s&display=block">' % f for f in FACES)
# Chrome loads IBM Plex Mono 500 but will not embed its program - the one
# face that resisted the split above, reproducibly. It is used only for small
# uppercase labels, chips and step numbers, where the weight difference is
# marginal, so print collapses Mono to a single weight rather than shipping a
# PDF that substitutes on someone else's machine.
replacement += chr(10) + (
    '<style>code, kbd, pre, .mono, .chip, .eyebrow, .board dt, .rail a .n, '
    'td.mono, ol.steps > li::before { font-weight: 400 !important; }</style>')

html = html.replace(link.group(0), replacement, 1)
io.open(TMP, 'w', encoding='utf-8', newline=chr(10)).write(html)

subprocess.run([
    CHROME, '--headless=new', '--disable-gpu', '--no-pdf-header-footer',
    '--run-all-compositor-stages-before-draw', '--virtual-time-budget=60000',
    '--print-to-pdf=' + OUT, 'file:///' + TMP,
], check=True, capture_output=True)

# ---- verify, properly: walk each descriptor's own dictionary ----
d = io.open(OUT, 'rb').read()

def enclosing_dict(pos):
    start = d.rfind(b'<<', 0, pos)
    depth, i = 0, start
    while i < len(d) - 1:
        if d[i:i + 2] == b'<<':
            depth += 1; i += 2; continue
        if d[i:i + 2] == b'>>':
            depth -= 1; i += 2
            if depth == 0:
                return d[start:i]
            continue
        i += 1
    return d[start:pos + 2000]

missing, total = [], 0
for m in re.finditer(rb'/Type\s*/FontDescriptor', d):
    dic = enclosing_dict(m.start())
    total += 1
    if b'/FontFile' not in dic:
        n = re.search(rb'/FontName\s*/([^\s/>\]]+)', dic)
        missing.append(n.group(1).decode() if n else '?')

print('pages : %d' % len(re.findall(rb'/Type\s*/Page[^s]', d)))
print('size  : %.0f KB' % (len(d) / 1024))
print('fonts : %d descriptors, %d embedded' % (total, total - len(missing)))
if missing:
    print('NOT EMBEDDED: ' + ', '.join(sorted(set(missing))))
    sys.exit(1)
