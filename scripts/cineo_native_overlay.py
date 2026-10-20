#!/usr/bin/env python3
"""Strict, repeatable Cineo P1 identity/privacy overlay on pinned Orbit sources.

An unsigned bootstrap experiment, not evidence of a working capture or export.
Fail closed if the inspected source layout changes.
"""
from __future__ import annotations

import argparse
import plistlib
import shutil
from pathlib import Path

BUNDLE_ID = "com.daniele21.cineo"


def replace_exact(text: str, before: str, after: str, count: int) -> str:
    matches = text.count(before)
    if matches != count:
        raise ValueError(f"Unsafe upstream drift: expected {count} of {before!r}, got {matches}")
    return text.replace(before, after, count)


def apply_overlay(root: Path) -> None:
    project = root / "Reco.xcodeproj" / "project.pbxproj"
    info_file = root / "Reco" / "Info.plist"
    main_file = root / "Reco" / "RecoMain.swift"
    app_file = root / "Reco" / "RecoApp.swift"
    delegate_file = root / "Reco" / "AppDelegate.swift"
    zoom_file = root / "Reco" / "Editor" / "ViewModel" / "EditorViewModel+Zooming.swift"
    editor_project_file = root / "Reco" / "Editor" / "Model" / "EditorProject.swift"
    repo_root = Path(__file__).resolve().parent.parent
    camera_source = repo_root / "Packages" / "CineoDirector" / "Sources" / "CineoDirector" / "CameraPlanner.swift"
    bridge_source = repo_root / "native" / "OrbitIntegration" / "CineoAutoZoomBridge.swift"
    bridge_tests = repo_root / "native" / "OrbitIntegration" / "CineoAutoZoomBridgeTests.swift"
    for extra in (zoom_file, editor_project_file, camera_source, bridge_source, bridge_tests):
        if not extra.is_file():
            raise FileNotFoundError(f"Cineo camera integration file missing: {extra}")
    for path in (project, info_file, main_file, app_file, delegate_file, root / "LICENSE"):
        if not path.is_file():
            raise FileNotFoundError(f"Orbit source tree incomplete: {path}")

    # Check all assumptions before writing any files.
    pbx = project.read_text()
    pbx = replace_exact(pbx, "INFOPLIST_KEY_CFBundleDisplayName = Orbit;",
                        "INFOPLIST_KEY_CFBundleDisplayName = Cineo;", 2)
    pbx = replace_exact(pbx, "PRODUCT_BUNDLE_IDENTIFIER = com.diip3sh.Reco;",
                        f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};", 2)
    product_name = 'PRODUCT_NAME = "$(TARGET_NAME)";'
    if pbx.count(product_name) != 4:
        raise ValueError("Unsafe upstream drift: expected two app and two test product-name settings")
    # Xcode app configurations occur before its tests; rename only app product.
    pbx = pbx.replace(product_name, "PRODUCT_NAME = Cineo;", 2)
    team = "DEVELOPMENT_TEAM = 6TF45WCU3B;"
    if pbx.count(team) < 4:
        raise ValueError("Unsafe upstream drift: signing team layout changed")
    pbx = pbx.replace(team, 'DEVELOPMENT_TEAM = "";')
    # Never ship Orbit's icon as a Cineo brand identity.
    # App product name can differ from its Swift import module. Upstream
    # @testable import Reco stays valid while bundled app is called Cineo.
    app_product_line = "PRODUCT_NAME = Cineo;\\n\\t\\t\\t\\tREGISTER_APP_GROUPS = YES;"
    module_line = "PRODUCT_NAME = Cineo;\\n\\t\\t\\t\\tPRODUCT_MODULE_NAME = Reco;\\n\\t\\t\\t\\tREGISTER_APP_GROUPS = YES;"
    pbx = replace_exact(pbx, app_product_line, module_line, 2)
    old_test_host = 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Reco.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Reco";'
    new_test_host = 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Cineo.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Cineo";'
    pbx = replace_exact(pbx, old_test_host, new_test_host, 2)
    pbx = replace_exact(pbx, "ASSETCATALOG_COMPILER_APPICON_NAME = Reco;",
                        'ASSETCATALOG_COMPILER_APPICON_NAME = "";', 2)

    with info_file.open("rb") as stream:
        info = plistlib.load(stream)
    for key in ("NSScreenCaptureUsageDescription", "NSMicrophoneUsageDescription", "NSCameraUsageDescription"):
        if key not in info:
            raise ValueError(f"Missing OS permission description: {key}")
    info["NSScreenCaptureUsageDescription"] = "Cineo needs Screen Recording access when you choose to record a screen or window."
    info["NSMicrophoneUsageDescription"] = "Cineo needs microphone access only when you enable microphone recording."
    info["NSCameraUsageDescription"] = "Cineo needs camera access only when you enable camera recording."
    # Upstream's UpdaterService checks this placeholder and does not start Sparkle.
    info["SUPublicEDKey"] = "SPARKLE_PUBLIC_KEY"
    info.pop("SUFeedURL", None)
    # Do not hijack Orbit's URL handler and style file types.
    for key in ("CFBundleURLTypes", "CFBundleDocumentTypes", "UTExportedTypeDeclarations"):
        info.pop(key, None)

    main = replace_exact(main_file.read_text(), "        ContainerMigration.run()\n",
                         "        // Cineo never imports Orbit sandbox data.\n", 1)
    app = replace_exact(app_file.read_text(), "Image(.menuBarIcon)",
                        'Image(systemName: "record.circle")', 1)
    delegate = replace_exact(delegate_file.read_text(), "        agentBridge.start()\n",
                             "        // P1: upstream local agent bridge disabled until explicit security review.\n", 1)

    # Reco uses PBXFileSystemSynchronizedRootGroup, so staged .swift files inside
    # Reco/Editor/Service are compiled into its native app without editing PBX.
    # Keep source-time zoom lane semantics; Orbit's TimeMap retimes for playback.
    old = "AutoZoomGenerator.segments(for: telemetry, duration: source.duration)"
    zoom_code = replace_exact(zoom_file.read_text(), old,
                              "CineoAutoZoomBridge.segments(for: telemetry, duration: source.duration)", 1)
    old = "AutoZoomGenerator.segments(for: $0, duration: source.duration)"
    project_code = replace_exact(editor_project_file.read_text(), old,
                                "CineoAutoZoomBridge.segments(for: $0, duration: source.duration)", 1)
    director = camera_source.read_text()
    for declaration in ("AttentionEvent", "CameraShot", "CameraPlanner"):
        director = replace_exact(director, f"public struct {declaration}:",
                                 f"nonisolated public struct {declaration}:", 1)
    # Orbit sets SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor; the helper
    # extension must also be explicitly nonisolated for synchronous sorting.
    director = replace_exact(director, "private extension AttentionEvent.Kind {",
                             "nonisolated extension AttentionEvent.Kind {", 1)
    
    project.write_text(pbx)
    with info_file.open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)
    main_file.write_text(main)
    app_file.write_text(app)
    delegate_file.write_text(delegate)
    zoom_file.write_text(zoom_code)
    editor_project_file.write_text(project_code)
    staging_service = root / "Reco" / "Editor" / "Service"
    (staging_service / "CineoCameraPlanner.swift").write_text(director)
    shutil.copy2(bridge_source, staging_service / "CineoAutoZoomBridge.swift")
    shutil.copy2(bridge_tests, root / "RecoTests" / "CineoAutoZoomBridgeTests.swift")

    print(f"Applied Cineo P1 overlay for {BUNDLE_ID} to {root}")
    print("Source license retained. Upstream migration, app updater, URL handler and agent bridge disabled.")
    print("Native editor new-recording and Regenerate Zooms now use CineoDirector; Orbit renderer unchanged.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Clean pinned Orbit checkout")
    apply_overlay(parser.parse_args().source.resolve())
