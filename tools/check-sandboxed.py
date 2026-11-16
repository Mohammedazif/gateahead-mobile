#!/usr/bin/env python3
"""Run cached Flutter tests/analyzer with a read-only SDK and no local sockets.

Normal development should use `flutter test` and `flutter analyze`. This runner
uses Flutter's standalone test mode when a sandbox prevents its WebSocket test
transport, and never downloads dependencies or changes the SDK.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def run(args, cwd, **kwargs):
    return subprocess.run([str(arg) for arg in args], cwd=cwd, check=True, timeout=180, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter-root", type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    launcher = shutil.which("flutter")
    sdk = args.flutter_root or (Path(launcher).resolve().parents[1] if launcher else None)
    if sdk is None:
        parser.error("Flutter was not found; pass --flutter-root for an installed SDK.")
    cache = sdk / "bin/cache"
    engine = cache / "artifacts/engine/linux-x64"
    config = project / ".dart_tool/package_config.json"
    if not config.exists():
        parser.error("Cached dependencies are missing. Run flutter pub get first.")
    with tempfile.TemporaryDirectory(prefix="gateahead-mobile-checks-") as folder:
        scratch = Path(folder)
        runner = scratch / "tests.dart"
        tests = sorted((project / "test").glob("*_test.dart"))
        runner.write_text(
            "import 'package:flutter_test/flutter_test.dart';\n"
            + "".join(f"import '{path.as_uri()}' as test{i};\n" for i, path in enumerate(tests))
            + "void main() {\n"
            + "".join(f"group('{path.stem}', test{i}.main);\n" for i, path in enumerate(tests))
            + "}\n"
        )
        kernel = scratch / "tests.dill"
        compiled = run([
            cache / "dart-sdk/bin/dartaotruntime",
            engine / "frontend_server_aot.dart.snapshot",
            "--sdk-root", cache / "artifacts/engine/common/flutter_patched_sdk",
            "--target", "flutter", "--packages", config,
            "--output-dill", kernel, runner,
        ], project, capture_output=True, text=True)
        if not kernel.exists() or not compiled.stdout.rstrip().endswith(" 0"):
            raise SystemExit(compiled.stdout + compiled.stderr)
        tested = run([
            engine / "flutter_tester", "--disable-vm-service", "--enable-checked-mode",
            "--non-interactive", "--enable-software-rendering", "--skia-deterministic-rendering",
            "--use-test-fonts", "--disable-asset-fonts", f"--packages={config}",
            f"--flutter-assets-dir={project / 'build/unit_test_assets'}", kernel,
        ], project, capture_output=True, text=True, env={**os.environ, "FLUTTER_TEST": "true"})
        print(tested.stdout, end="", flush=True)
        print(tested.stderr, end="", flush=True)
        # Flutter's standalone reporter exits zero even for failed assertions.
        if "All tests passed!" not in tested.stdout or "Some tests failed." in tested.stdout:
            raise SystemExit(1)
        analyzer = scratch / "analyze.dart"
        analyzer.write_text("""
import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
Future<void> main(List<String> args) async {
  final collection = AnalysisContextCollection(
    includedPaths: ['${args[0]}/lib', '${args[0]}/test'], sdkPath: args[1]);
  var files = 0, diagnostics = 0;
  for (final context in collection.contexts) {
    for (final path in context.contextRoot.analyzedFiles().where((path) => path.endsWith('.dart'))) {
      files++;
      final result = await context.currentSession.getErrors(path);
      if (result is ErrorsResult) {
        for (final error in result.diagnostics) { diagnostics++; print('$path: $error'); }
      }
    }
  }
  print('Analyzed $files Dart files; $diagnostics diagnostics.');
  await collection.dispose();
  exit(diagnostics == 0 ? 0 : 1);
}
""")
        run([
            cache / "dart-sdk/bin/dart",
            f"--packages={sdk / 'packages/flutter_tools/.dart_tool/package_config.json'}",
            analyzer, project, cache / "dart-sdk",
        ], project)


if __name__ == "__main__":
    main()
