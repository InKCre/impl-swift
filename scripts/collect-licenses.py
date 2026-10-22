"""Bundle exact dependency licenses and notices; never fetch moving upstream at package time."""
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[1]
output = pathlib.Path(sys.argv[1])
parts = [(root / "THIRD_PARTY_NOTICES.md").read_text(), (root / "LICENSE").read_text()]
for path in sorted((root / "extensions/capture/Legal").rglob("*")):
    if path.is_file():
        parts += [str(path.relative_to(root)), path.read_text()]
for pin in json.loads((root / "Package.resolved").read_text())["pins"]:
    checkout = root / ".build/checkouts" / pin["identity"]
    files = sorted(p for p in checkout.rglob("*") if p.is_file() and
                   p.name.upper().startswith(("LICENSE", "LICENCE", "NOTICE", "COPYING")))
    if not files:
        raise SystemExit(f"Missing license for {pin['identity']}")
    parts.append(f"{pin['identity']} {pin['state'].get('version', '')}\n{pin['location']}\nrevision {pin['state']['revision']}")
    for path in files:
        parts += [str(path.relative_to(checkout)), path.read_text(errors="strict")]
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text("\n\n" + ("\n\n" + "=" * 72 + "\n\n").join(parts))
