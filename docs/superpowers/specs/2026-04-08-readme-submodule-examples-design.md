# README Submodule Typical Examples Design

- Date: 2026-04-08
- Repo: `RYKit`
- Authoring mode: Brainstorming -> Design approved by user

## 1. Goal

Add representative examples for all `RYKitCore` submodules in `README.md`, with bilingual coverage (English + 中文), while keeping examples concise and focused on core API calls.

## 2. Scope

In scope:

- Edit only `README.md`.
- Add English and Chinese sections for typical examples by submodule.
- Cover all Core submodules:
  - `Associatable`
  - `Async`
  - `Codable`
  - `Collections`
  - `Combine`
  - `Extensions`
  - `KV`
  - `Lock`
  - `Reachability`
  - `TimeoutTask`
- Align existing `Http` and `Stomp` examples to the same concise style.

Out of scope:

- Any Swift source changes under `Classes/`.
- New docs files outside README.
- Refactoring module APIs or renaming modules.

## 3. README Structure Design

### English

Keep existing `Package and Module Mapping`, then append:

- `### Typical Examples by Core Submodule`
- Ordered blocks for each Core submodule, matching module order in mapping.
- Keep `Http` and `Stomp` examples; adjust to consistent “core-call focused” style.

### 中文

Keep existing `包与模块对应关系`, then append:

- `### 各子模块典型示例`
- Same module ordering and semantic parity with English.
- Preserve concise style and short code blocks.

## 4. Example Allocation (By Complexity)

Allocation rules (approved by user):

- Simple modules: 1 example each
- Complex modules: 2 examples each

Planned distribution:

1. `Associatable`: 1
2. `Async`: 1
3. `Codable`: 2 (`@Default`, `@PreferValue`/`@FromStringValue`)
4. `Collections`: 2 (`Queue`, `WeakMap`)
5. `Combine`: 2 (`store(in:)`, `DebounceCallback`)
6. `Extensions`: 1
7. `KV`: 2 (`TinyKV`, `TinyBufferedKV + flush`)
8. `Lock`: 2 (`@ThreadSafe`, `ReadWriteLock`)
9. `Reachability`: 1
10. `TimeoutTask`: 2 (`OnceTimeoutTask`, `OnceTimeoutTaskQueue`)
11. `Http`: existing main request example retained with concise polishing
12. `Stomp`: existing subscribe example retained with concise polishing

## 5. Content Style Rules

- Prefer short, focused examples showing core API usage.
- Do not include full runnable scaffolding unless required.
- Keep each snippet typically within 6-12 lines.
- Keep one clear intent per snippet.
- Maintain bilingual semantic parity (same intent in both languages).

## 6. Data Flow / Reader Experience

1. Reader sees module mapping.
2. Reader immediately gets a matching “typical usage” snippet for each submodule.
3. Reader can compare English/中文 sections with same module sequence.
4. Reader can quickly locate an API pattern before checking source code.

## 7. Error Handling and Risk Controls

Documentation-level constraints:

- Snippets should include minimal failure branch shape where relevant (`switch` or `do/catch`) without business detail.
- Avoid introducing undocumented behavior claims.
- Do not alter install/version/API compatibility statements.

Change-risk controls:

- Single-file documentation edit (`README.md`).
- No behavior or binary impact.

## 8. Validation Criteria

Must pass all:

1. English + 中文 both include all Core submodule examples.
2. Module order is consistent between languages.
3. Snippet counts match complexity allocation.
4. Markdown headings and code fences are valid.
5. Existing install/version/module mapping sections remain intact.

Verification method:

- Manual `git diff README.md` review for parity and scope.
- Quick scan for heading/fence correctness.

## 9. Implementation Notes for Next Phase

- Insert new sections near existing module mapping blocks to keep discovery flow.
- Reuse existing HTTP/STOMP examples, only trim/reformat where needed for style consistency.
- Keep naming and terminology aligned with existing README conventions.
