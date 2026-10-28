#!/usr/bin/env python3
"""Enable simulator-only parity fixtures in a copy of Xcode's test-run file.

Keep the copy beside the original so __TESTROOT__ still resolves correctly.
This configures tests only; it never launches or writes into an app container.
"""
import argparse
import plistlib
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("test_run", type=Path)
parser.add_argument("fixture", type=Path)
args = parser.parse_args()
fixture = args.fixture.resolve(strict=True)
source = args.test_run.resolve(strict=True)
config = plistlib.loads(source.read_bytes())
configured = set()
for configuration in config.get("TestConfigurations", []):
    for target in configuration.get("TestTargets", []):
        name = target.get("BlueprintName")
        if name in {"DeuceMateTests", "DeuceMateUITests"}:
            environment = target.setdefault("EnvironmentVariables", {})
            environment["DEUCEMATE_NATIVE_PARITY"] = "1"
            environment["DEUCEMATE_NATIVE_FIXTURE_PATH"] = str(fixture)
            configured.add(name)
if configured != {"DeuceMateTests", "DeuceMateUITests"}:
    raise SystemExit("Expected both iPhone test targets in a version-2 .xctestrun file.")
output = source.with_name(source.stem + "_NativeParity.xctestrun")
output.write_bytes(plistlib.dumps(config))
print(output)
