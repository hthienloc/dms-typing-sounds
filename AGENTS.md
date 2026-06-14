# AI Agent Workflow for DMS Plugins

This document describes the standardized workflow, best practices, and constraints for AI agents developing plugins for **Dank Material Shell (DMS)**.

## Core Principles

1. **Inheritance**: Always use `PluginComponent` as the root of the widget and `PluginSettings` for the settings page.
2. **Robustness**: Access `pluginData` properties using the nullish coalescing operator (`??`) to provide safe defaults before settings are fully loaded.
3. **UI Consistency**: Use DMS design tokens from `Theme` (e.g., `Theme.surfaceText`, `Theme.spacingM`, `Theme.cornerRadius`).
4. **Sizing & Layout Constraints (CRITICAL)**:
   - **No Custom Item Wrappers**: Do not wrap your horizontal or vertical pill layout delegates in static `Item` components with custom dimensions. 
   - **Root Row/Column Enforced**: Use a `Row` root for `horizontalBarPill` and a `Column` root for `verticalBarPill`. This allows DankBar/Quickshell to automatically calculate implicit sizes, resulting in a perfectly tight visual fit with no bloated padding.
5. **No Custom Setting Card Layouts**: Import and utilize standard `SettingsCard` components from `dms-common` for settings groups instead of manually defining `StyledRect` frames.

---

## Development Steps

### 1. Planning
- Identify the core functionality and required permissions (`plugin.json`).
- Define the interaction model (Left-click for popouts/toggle, Right-click for quick actions/logging).

### 2. Implementation
- **Initial Setup**: Create a symbolic link directly from the repository folder pointing to `~/.config/DankMaterialShell/plugins/<id>` to test live changes instantly in the running desktop environment.
- **plugin.json**: Ensure the `id` is unique and contains NO redundant words (e.g., use `"hydrate"`, never `"dmsHydrate"`).
- **Settings UI**: Replicate `SettingsCard` and default standard components.
- **Visuals & Color Tokens**: **NEVER hardcode colors**. Respect user themes by always querying dynamic tokens (e.g. `Theme.primary`, `Theme.warning`, `Theme.surfaceText`).

### 3. Documentation (CRITICAL)
- **Concise README**: The project README must be extremely short, concise, and structured exactly like the template's standard sections:
  1. **Intro & Screenshot**
  2. **Install** (showing `dms-common` pre-requisite and clean manual clone commands)
  3. **Features** — **MUST focus entirely on what core problem the plugin solves** (e.g., preventing eye strain, back pain, focus distraction, workflow fatigue), rather than bragging about flashy animations or showing off complex visual widgets.
  4. **Usage** (clean Markdown gesture table)
  5. **License** (GPL-3.0)
  6. **Roadmap / TODO** (checkbox list of future additions)

---

## Publication & Registration

- **GitHub Upload**: Initialize git, commit all files, and create a public repository using `gh repo create dms-<plugin-id> --public --source=. --remote=origin --push`.
- **Registry Entry**:
  - Navigate to `dms-plugin-registry`.
  - Add standard schema under `plugins/hthienloc-<plugin-id>.json`.
  - Ensure the screenshot URL references the `master` or `main` branch asset.
