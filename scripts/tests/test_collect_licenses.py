"""验证最终通知包含固定依赖的许可，以及本项目品牌的来源与使用边界。"""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class CollectLicensesTests(unittest.TestCase):
    def test_bundles_brand_provenance_without_relaxing_missing_license_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            script = root / "scripts/collect-licenses.py"
            shutil.copyfile(Path(__file__).resolve().parents[1] / script.name, script)
            (root / "LICENSE").write_text("Host license")
            (root / "THIRD_PARTY_NOTICES.md").write_text("Host notices")
            logo = root / ".build/checkouts/ui/assets/logo"
            logo.mkdir(parents=True)
            (logo / "README.zh-CN.md").write_text("品牌资源不另行授予商标使用权限。")
            provenance = logo / "PROVENANCE.json"
            provenance.write_text('{"source": "fixed brand source"}')
            dependency = root / ".build/checkouts/dependency"
            dependency.mkdir()
            (dependency / "LICENSE").write_text("Dependency full license")
            pins = [
                {"identity": "ui", "location": "https://github.com/InKCre/ui.git",
                 "state": {"revision": "fixed-ui-revision"}},
                {"identity": "dependency", "location": "https://example.com/dependency.git",
                 "state": {"revision": "fixed-dependency-revision"}},
            ]
            (root / "Package.resolved").write_text(json.dumps({"pins": pins}))
            output = root / "notices.txt"

            def collect():
                return subprocess.run(["python3", str(script), str(output)], capture_output=True, text=True)

            result = collect()
            self.assertEqual(result.returncode, 0, result.stderr)
            bundled = output.read_text()
            for value in ("Dependency full license", "品牌资源不另行授予商标使用权限。",
                          "fixed brand source", "fixed-ui-revision", "fixed-dependency-revision"):
                self.assertIn(value, bundled)

            pins[0]["location"] = "https://example.com/ui.git"
            (root / "Package.resolved").write_text(json.dumps({"pins": pins}))
            result = collect()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Missing license for ui", result.stderr)

            pins[0]["location"] = "https://github.com/InKCre/ui.git"
            (root / "Package.resolved").write_text(json.dumps({"pins": pins}))
            provenance.unlink()
            result = collect()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PROVENANCE.json", result.stderr)
