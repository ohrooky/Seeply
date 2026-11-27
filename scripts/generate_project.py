#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project. Standard library only; no XcodeGen."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()


def encode(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, dict):
        return "{\n" + "".join(f"{indent}\t{json.dumps(k)} = {encode(v, depth + 1)};\n" for k, v in value.items()) + indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{indent}\t{encode(v, depth + 1)},\n" for v in value) + indent + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)


def main():
    objects = {}

    def obj(object_key, isa, **kwargs):
        key = uid(object_key)
        if key in objects:
            raise ValueError("Duplicate project object: " + object_key)
        objects[key] = dict(isa=isa, **kwargs)
        return key

    def file(name, path, kind, tree="<group>"):
        return obj(name, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree=tree)

    def build_file(name, reference):
        return obj(name, "PBXBuildFile", fileRef=reference)

    source_builds = []
    source_groups = []
    for directory in ("App", "Core", "Models", "Services", "Viewer", "UI"):
        children = []
        for path in sorted((ROOT / "Seeply" / directory).glob("*.swift")):
            reference = file("file:" + str(path.relative_to(ROOT)), path.name, "sourcecode.swift")
            children.append(reference)
            source_builds.append(build_file("build:" + str(path.relative_to(ROOT)), reference))
        source_groups.append(obj("group:" + directory, "PBXGroup", children=children, path=directory, sourceTree="<group>"))
    asset = file("assets", "Assets.xcassets", "folder.assetcatalog")
    samples = file("samples", "Samples", "folder")
    info = file("info", "Info.plist", "text.plist.xml")
    entitlements = file("entitlements", "Seeply.entitlements", "text.plist.entitlements")
    source_groups.append(obj("resources", "PBXGroup", children=[asset, samples, info, entitlements], path="Resources", sourceTree="<group>"))
    app_group = obj("appGroup", "PBXGroup", children=source_groups, path="Seeply", sourceTree="<group>")

    test_children = []
    test_builds = []
    for path in sorted((ROOT / "SeeplyTests").glob("*.swift")):
        reference = file("file:" + str(path.relative_to(ROOT)), path.name, "sourcecode.swift")
        test_children.append(reference)
        test_builds.append(build_file("build:" + str(path.relative_to(ROOT)), reference))
    fixtures = file("fixtures", "Fixtures", "folder")
    test_children.append(fixtures)
    tests_group = obj("testsGroup", "PBXGroup", children=test_children, path="SeeplyTests", sourceTree="<group>")
    readme = file("readme", "README.md", "net.daringfireball.markdown")
    review = file("review", "REVIEW.md", "net.daringfireball.markdown")
    validation = file("validation", "VALIDATION.md", "net.daringfireball.markdown")
    app_product = obj("appProduct", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="Seeply.app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = obj("testProduct", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path="SeeplyTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    products = obj("products", "PBXGroup", name="Products", children=[app_product, test_product], sourceTree="<group>")
    main_group = obj("mainGroup", "PBXGroup", children=[app_group, tests_group, readme, review, validation, products], sourceTree="<group>")

    def phase(name, isa, files):
        return obj(name, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)

    app_sources = phase("appSources", "PBXSourcesBuildPhase", source_builds)
    app_frameworks = phase("appFrameworks", "PBXFrameworksBuildPhase", [])
    app_resources = phase("appResources", "PBXResourcesBuildPhase", [build_file("assetBuild", asset), build_file("sampleBuild", samples)])
    test_sources = phase("testSources", "PBXSourcesBuildPhase", test_builds)
    test_frameworks = phase("testFrameworks", "PBXFrameworksBuildPhase", [])
    test_resources = phase("testResources", "PBXResourcesBuildPhase", [build_file("fixtureBuild", fixtures)])

    common = {
        "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "SWIFT_VERSION": "5.0",
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "SWIFT_STRICT_CONCURRENCY": "targeted", "SWIFT_EMIT_LOC_STRINGS": "NO",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR", "CLANG_WARN_UNREACHABLE_CODE": "YES",
    }

    def config_list(name, settings):
        configs = []
        for variant in ("Debug", "Release"):
            merged = dict(settings)
            if name == "project":
                merged.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if variant == "Debug" else "-O",
                               "DEBUG_INFORMATION_FORMAT": "dwarf" if variant == "Debug" else "dwarf-with-dsym"})
                if variant == "Debug":
                    merged.update({"ENABLE_TESTABILITY": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"})
            configs.append(obj(name + variant, "XCBuildConfiguration", buildSettings=merged, name=variant))
        return obj(name + "Configs", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

    project_configs = config_list("project", common)
    # Keep the original application identity so the rename preserves preferences
    # and sandbox identity. Product/module/scheme names are independently Seeply.
    app_configs = config_list("app", {
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "local.luma.viewer",
        "INFOPLIST_FILE": "Seeply/Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": "Seeply/Resources/Seeply.entitlements", "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-",
        "ENABLE_APP_SANDBOX": "YES", "ENABLE_HARDENED_RUNTIME": "YES",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
    })
    test_configs = config_list("tests", {
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "local.luma.viewer.tests",
        "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Seeply.app/Contents/MacOS/Seeply", "BUNDLE_LOADER": "$(TEST_HOST)",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks"],
    })
    app = obj("appTarget", "PBXNativeTarget", buildConfigurationList=app_configs,
              buildPhases=[app_sources, app_frameworks, app_resources], buildRules=[], dependencies=[],
              name="Seeply", productName="Seeply", productReference=app_product, productType="com.apple.product-type.application")
    proxy = obj("testProxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1, remoteGlobalIDString=app, remoteInfo="Seeply")
    dependency = obj("testDependency", "PBXTargetDependency", target=app, targetProxy=proxy)
    tests = obj("testTarget", "PBXNativeTarget", buildConfigurationList=test_configs,
                buildPhases=[test_sources, test_frameworks, test_resources], buildRules=[], dependencies=[dependency],
                name="SeeplyTests", productName="SeeplyTests", productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
    project = obj("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "LastSwiftUpdateCheck": "1600",
                  "TargetAttributes": {app: {"CreatedOnToolsVersion": "16.0"}, tests: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app}}},
                  buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en",
                  hasScannedForEncodings=0, knownRegions=["en", "zh-Hant", "Base"], mainGroup=main_group,
                  productRefGroup=products, projectDirPath="", projectRoot="", targets=[app, tests])
    project_dir = ROOT / "Seeply.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    content = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
    (project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(content) + "\n")

    def reference(parent, target, product, name):
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target,
                      BuildableName=product, BlueprintName=name, ReferencedContainer="container:Seeply.xcodeproj")

    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    action = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(action, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
    reference(entry, app, "Seeply.app", "Seeply")
    test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    testables = ET.SubElement(test, "Testables")
    testable = ET.SubElement(testables, "TestableReference", skipped="NO")
    reference(testable, tests, "SeeplyTests.xctest", "SeeplyTests")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
    runnable = ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0")
    reference(runnable, app, "Seeply.app", "Seeply")
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), app, "Seeply.app", "Seeply")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme, space="  ")
    scheme_path = project_dir / "xcshareddata" / "xcschemes" / "Seeply.xcscheme"
    scheme_path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(scheme).write(scheme_path, encoding="UTF-8", xml_declaration=True)
    workspace = project_dir / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
    print(f"Generated {project_dir.name}: {len(source_builds)} app sources, {len(test_builds)} test sources")


if __name__ == "__main__":
    main()
