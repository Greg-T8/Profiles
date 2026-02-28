# Sync Dashboard Project Colors from Workspace Title Bars

## Objective

Update the `dashboard.projectData` colors in the user's VS Code `settings.json` so
that each project tile color matches the `titleBar.activeBackground` from the
project's `.code-workspace` file.

## Source

Scan **all** subfolders (recursively) under `~/LocalCode` for `.code-workspace`
files.

## Steps

1. **Enumerate workspace files** — Recursively find every `.code-workspace` file
   under `~/LocalCode`. If a subfolder does not contain a `.code-workspace` file,
   skip it.

2. **Extract title bar color** — In each `.code-workspace` file, look for:

   ```jsonc
   "workbench.colorCustomizations": {
     "titleBar.activeBackground": "<color>"
   }
   ```

   If the workspace file has no `titleBar.activeBackground` value, skip it.

3. **Match to dashboard entry** — In the user's `settings.json`, locate the
   `dashboard.projectData` array. For each workspace file found in step 1, find
   the project entry whose `path` matches that workspace file's path.

4. **Update the color** — Set the project entry's `"color"` value to the
   `titleBar.activeBackground` hex value extracted in step 2. Only update entries
   where the color actually differs.

5. **Report results** — After all updates are applied, list:
   - Each project updated: name, old color, new color.
   - Any workspace files skipped (no `titleBar.activeBackground` or no matching
     dashboard entry) and why.

## Rules

- Do **not** modify any other fields in `dashboard.projectData`.
- Do **not** create, delete, or rename any project entries.
- Path matching should be case-insensitive and treat `/` and `\` as equivalent.
- Preserve the existing JSON formatting and comment style in `settings.json`.
