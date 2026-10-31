# Flash Tags

Add, remove or replace a tag across selected objects. Preview the batch first; unrelated tags are preserved.

## Install

1. Download this repository as a ZIP and extract it. No package installation is needed to use the plugin.
2. In a separate Studio test place, use Explorer's **Insert from File** action to insert `FlashTags.rbxmx`.
3. Select the root Script named `FlashTags` (it has five child ModuleScripts) and choose **Save as Local Plugin**.
4. Remove the imported Script from the place. Open **Flash Tags → Tags** on the Plugins toolbar.

The plugin runs in edit mode. Scans and edits are refused during a play test.

Preview makes no edits. Selection or option changes clear the plan. Apply rechecks changed targets and uses one Studio undo recording. A failed write asks Studio to cancel the batch. Up to 100 preview rows are shown, but Apply includes every change in the plan. Use a smaller selection if you want every row visible. Verify Undo and Redo on a copy before important work.

## Use it

Select objects in Explorer. Choose **Add**, **Remove** or **Replace**, enter the tag, and preview. Replace also needs a different replacement tag. Use **Include descendants** when selecting a Model or folder, then apply the reviewed batch.

- Add skips objects already carrying the tag.
- Remove skips objects without it.
- Replace only affects objects with the old tag. It adds the replacement and removes the old tag. If the replacement was already present, it stays present.

For example, replace `Door` with `Interactable` on a selected building, then use Flash Inspect to check its interaction IDs. This plugin edits tags, not attributes or behavior scripts; it cannot update tag strings used in other code.

## Limits

- Up to 500 selected roots, 5000 discovered objects and 1000 target objects. Overlapping selections are deduplicated. Selecting services themselves is refused.
- Tag names use 1–64 ASCII letters, digits, underscores, periods or hyphens. This is the tool's naming policy; it does not cover every string Roblox may accept as a tag. Names are case-sensitive.
- Selection-only mode does not expand descendants. Include-descendants mode includes the selected roots as well as their descendants.
- Apply rechecks parents and the relevant tag states. Unrelated tag changes are allowed and preserved. Newly added descendants and targets omitted as no-ops are not added to an existing preview.
- Other plugins or scripts can listen for tag changes and make their own edits. The undo recording covers this tool's batch; it cannot promise to reverse arbitrary actions taken by other code.

## Inputs and outputs

`Rules.plan(rows, options)` takes presence records and `{mode, tag, replacement}` and returns changed tag operations. `Scope` bounds and deduplicates traversal. `Adapter` uses Instance's `HasTag`, `AddTag` and `RemoveTag` methods. It does not delete objects or change script source.

See Roblox's [Instance API](https://create.roblox.com/docs/reference/engine/classes/Instance) and [tag behavior](https://create.roblox.com/docs/reference/engine/classes/CollectionService).

## Development and tests

Source is in `src`. The dock panel follows Studio's theme. There are no runtime packages, external assets, file uploads, telemetry or network requests. The UI and scope helpers are shared with the other Flash plugins; each repository has its own copy so it can be installed independently.

Rebuild with Python 3.11+:

```sh
python build.py
python -m unittest discover -s tests -v
```

Run the Luau checks with Lune 0.11.1:

```sh
lune run tests/run
```

GitHub Actions compiles every source file, runs scope/rule/adapter checks with fake Studio objects, verifies the packaged source and checks reproducible builds. The editing plugins also test undo-recording commit/cancel behavior with a fake history service. Lune is installed on the CI runner, not on your PC.

**The dock widget, local-plugin installation and real Studio engine behavior have not been verified live.** See [Studio checks](docs/STUDIO-CHECKS.md). A passing automated test is not a live Studio compatibility guarantee.

MIT licensed; see [LICENSE](LICENSE).
