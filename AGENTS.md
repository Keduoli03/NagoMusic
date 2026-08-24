# AGENTS.md

This guide is for coding agents working in `nagomusic` (Flutter/Dart).
It documents the build/lint/test workflow and the code conventions used in this repo.

## 1) Project Snapshot

- Stack: Flutter app (Dart SDK `^3.10.8`, Material 3).
- Primary target in docs/CI: Android.
- Main source dirs: `lib/`, `test/`, platform folders (`android/`, `ios/`, `web/`, etc.).
- Entry point: `lib/main.dart`.
- App root widget: `NagoMusicApp` in `lib/app/app.dart`.
- Lints: `flutter_lints` via `analysis_options.yaml`.

## 2) Setup Commands

Run from repository root: `F:\ALL\Music\nagomusic`.

```bash
flutter --version
flutter pub get
```

If tooling or generated files seem stale:

```bash
flutter clean
flutter pub get
```

## 3) Build / Run Commands

Local debug run:

```bash
flutter run
```

Release APK build:

```bash
flutter build apk --release --split-per-abi
```

Optional platform checks (if needed by task):

```bash
flutter build ios
flutter build web
flutter build windows
```

## 4) Lint / Format Commands

Static analysis (primary lint gate):

```bash
flutter analyze
```

Formatting (preferred before commit):

```bash
dart format .
```

Tip: format changed files first, then run full `flutter analyze`.

UI 规范门禁（第二道栅栏，独立于 `flutter analyze`）：

```bash
bash tool/ui_lint.sh            # 与基线比对，任何一项指标变多就退出码 1
bash tool/ui_lint.sh --report   # 只打印当前各项计数，不比对
bash tool/ui_lint.sh --update   # 把当前计数写回 tool/ui_lint_baseline.txt
```

- **改动任何页面 UI 之前先提交本次改动，改完后、提交前跑一次 `bash tool/ui_lint.sh`**。
  它统计 `fontSize:` / `EdgeInsets.*` / `SizedBox(height|width: 数字)` /
  `BorderRadius.circular(` / `Color(0x` / `Colors.white|black|grey` /
  `appBar: AppBar(` / `AlertDialog(` / `showSnackBar(` /
  `SwitchListTile|CupertinoSwitch(` 这类散值写法在 `lib/` 下的出现次数，
  与 `tool/ui_lint_baseline.txt` 比对，只要求"不新增"，不要求存量归零。
- 新 UI 代码一律走 `lib/app/theme/tokens.dart` 里的 `AppColors` /
  `AppRadii` / `AppSpacing` / `AppTypography`，不要在页面里手写
  `fontSize:` / `Color(0xFF...)` / `BorderRadius.circular(数字)` 等散值。
- `--update` **只在真正还清了一批技术债之后**才用；不要为了让红变绿而
  在改动里顺手 `--update` 掩盖新增的违规。
- 本门禁不接入 `flutter test`——样式规范失败不应该表现成用例失败。

## 5) Test Commands

Run all tests:

```bash
flutter test
```

Run a single test file (important):

```bash
flutter test test/lyrics_parser_test.dart
```

Run a single test by name pattern (important):

```bash
flutter test test/lyrics_parser_test.dart --plain-name "parse translation line with same timestamp"
```

Run widget test file:

```bash
flutter test test/widget_test.dart
```

Machine-readable output (CI/debug tooling):

```bash
flutter test --reporter expanded
```

**`flutter test` alone is no longer sufficient.** `packages/bili_api` is a
separate local package (path dependency) with its own `test/`; the root
`flutter test` runner does not recurse into it. Use `tool/test_all.sh` to run
the root suite and every local package's suite in one go, failing if any of
them fails:

```bash
bash tool/test_all.sh
```

## 6) CI/Release Notes

- Workflow file: `.github/workflows/build-release.yml`.
- On push to `main`/`master` when `pubspec.yaml` changes (or manual dispatch), CI:
  - sets up Flutter stable + Java 17,
  - runs `flutter pub get`,
  - builds release APKs split per ABI,
  - creates GitHub release assets.
- Signing is secret-driven (`ANDROID_KEYSTORE_BASE64`, signing password/alias/key).

## 7) Repository-Specific Coding Conventions

These conventions are inferred from current code and should be preserved.

### Imports

- Order imports in groups:
  1. Dart SDK imports (`dart:*`),
  2. package imports (`package:*`),
  3. relative project imports (`../` / `./`).
- Keep one import per line.
- Prefer relative imports within `lib/` modules unless package import is clearer for tests/public API.
- Avoid unused imports; keep analyzer clean.

### Formatting and Structure

- Use `dart format` output as source of truth.
- Keep functions focused; extract helpers when a method grows significantly.
- Prefer trailing commas in multiline widget trees/argument lists for stable formatting.
- Avoid adding comments unless logic is non-obvious.

### Types and Null Safety

- The codebase is null-safe; keep strict null handling.
- Prefer explicit types when they improve readability; `final` is common for locals.
- Use `const` constructors/widgets where possible.
- Use `required` named parameters for mandatory inputs.
- Encode optionality intentionally (`Type?`) and guard before use.

### Naming

- Classes/enums/types: `PascalCase` (e.g., `PlayerService`, `SourceItem`).
- Files: `snake_case.dart`.
- Methods/variables/fields: `lowerCamelCase`.
- Private members: leading underscore (e.g., `_init`, `_prefsThemeMode`).
- Constants: `static const` with meaningful prefixes (e.g., `_prefs...`, `_default...`).

### State Management Patterns

- Existing patterns: `ValueNotifier`, `signals`, and service singletons.
- For UI state that must trigger rebuilds, follow existing notifier/signal style in nearby files.
- Avoid introducing a new state-management framework unless explicitly requested.

### Async and Lifecycle Safety

- In `StatefulWidget` async flows, check `mounted` before UI updates/navigation.
- Dispose owned notifiers/controllers/subscriptions in `dispose()`.
- In services, clean up timers/streams when adding new long-lived resources.
- Prefer `Future<void>` for async side-effect methods.

### Error Handling and Logging

- Wrap fallible IO/network/database calls in `try/catch` where failures are expected.
- Do not swallow errors silently; at minimum log in debug builds.
- Follow existing logging style: `if (kDebugMode) debugPrint(...)`.
- Provide safe fallback behavior on failure (defaults, retries, or early returns).

### UI and Theming

- Respect existing Material 3 + dynamic color setup in `lib/app/app.dart`.
- Reuse shared components under `lib/components/` before creating new primitives.
- Keep theme-dependent colors derived from `Theme.of(context).colorScheme` when possible.

### Data/Service Layer

- Service classes live under `lib/app/services/`; keep side effects there rather than UI layer.
- Repositories/DAO patterns already exist (`SongDao`, WebDAV repositories); extend them consistently.
- For persistent settings, follow the `SharedPreferences` pattern in `settings_state.dart`:
  - define key constants,
  - expose notifier/signal,
  - implement `ensureLoaded()` and setter methods.

## 8) Testing Expectations for Agents

- For logic-only changes: run targeted tests first, then `flutter analyze`.
- For UI changes: run impacted widget test files (or add/update tests if needed).
- For parser/service changes: add or update focused unit tests in `test/`.
- Prefer smallest useful test command during iteration; run broader suite before handoff.

## 9) Cursor/Copilot Rule Files

Checked paths:

- `.cursorrules`
- `.cursor/rules/`
- `.github/copilot-instructions.md`

Current status in this repository: no Cursor rule files or Copilot instruction file were found.
If these files are added later, update this document and treat them as higher-priority agent instructions.

## 10) Practical Agent Workflow

1. Read nearby code and follow local patterns before editing.
2. Make minimal, scoped changes.
3. Run `dart format` on touched files.
4. Run the most relevant single test(s).
5. Run `flutter analyze`.
6. Summarize what changed, what was run, and any remaining risks.

Keeping changes small, idiomatic, and validated is preferred over large refactors.
