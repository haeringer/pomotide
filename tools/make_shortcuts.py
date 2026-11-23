#!/usr/bin/env python3
"""Generate and sign the two Shortcuts that PomoTide runs to switch Focus.

Usage: tools/make_shortcuts.py

Writes Resources/Shortcuts/PomoTide Focus On.shortcut and ... Off.shortcut.
Signing (`shortcuts sign --mode anyone`) needs a Mac signed in to iCloud; the
signed files are committed, so builds do not need this step.
"""
import plistlib
import subprocess
import tempfile
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Resources" / "Shortcuts"
DND = {"Identifier": "com.apple.donotdisturb.mode.default", "DisplayString": "Do Not Disturb"}


def workflow(enabled):
    return {
        "WFWorkflowClientVersion": "2700.0.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59511},
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowImportQuestions": [],
        "WFQuickActionSurfaces": [],
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowActions": [
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
                "WFWorkflowActionParameters": {"Enabled": 1 if enabled else 0, "FocusModes": DND},
            }
        ],
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for enabled, suffix in ((True, "On"), (False, "Off")):
            name = f"PomoTide Focus {suffix}"
            unsigned = Path(tmp) / f"{name}.shortcut"
            unsigned.write_bytes(plistlib.dumps(workflow(enabled), fmt=plistlib.FMT_BINARY))
            subprocess.run(
                ["shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(OUT / f"{name}.shortcut")],
                check=True,
            )
            print("signed", name)


if __name__ == "__main__":
    main()
