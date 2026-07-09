# Obsidian Plugins

This vault assistant uses a few Obsidian community plugins. Install them from Settings → Community plugins → Browse.

## Required

### Dataview

Treats your vault as a database. The assistant uses `[key:: value]` markers for KPI data — commits, issues done, sessions, health score.

```markdown
[commits:: 5]
[issues_done:: 3]
[sessions:: 2]
```

Dataview queries also auto-populate the weekly review stats table.

**Install:** `obsidian://show-plugin?id=dataview` or search "Dataview" in community plugins.

### Obsidian Charts

Renders KPI trend charts in your weekly review. The assistant generates a ````chart` codeblock with health score, review rate, and project data over the last 4 weeks.

```markdown
````chart
type: line
title: KPI Trend W28
series:
  - title: Health Score
    data: [2, 2, 3, 3]
````
```

**Install:** `obsidian://show-plugin?id=obsidian-charts` or search "Charts" in community plugins.

### Templater

Lets you use dynamic template syntax like `<% tp.date.now("YYYY-MM-DD") %>` in your daily note template. The assistant templates rely on this for auto-filling dates.

**Install:** `obsidian://show-plugin?id=templater-obsidian` or search "Templater" in community plugins.

**Settings:**
- Set template folder: `templates/`
- Enable "Trigger Templater on new file creation"

## Optional

### Obsidian Git

Auto-commits and pushes your vault changes. The daily-cron script runs git pull/push, but Obsidian Git adds a safety net for manual edits.

**Install:** `obsidian://show-plugin?id=obsidian-git` or search "Obsidian Git".

### Calendar

Shows a calendar view in the sidebar. Lets you jump between daily notes. Not required by the assistant, but makes navigation faster.

**Install:** `obsidian://show-plugin?id=calendar` or search "Calendar".

### gEvent (Google Calendar)

Embeds a Google Calendar view inside your daily note. The ````gEvent` codeblock renders your schedule inline. See [google-calendar-setup.md](google-calendar-setup.md) for OAuth instructions.

```markdown
> [!calendar]- Jadwal
> ```gEvent
> date: 2026-07-09
> type: day
> ```

**Install:** `obsidian://show-plugin?id=google-calendar` or search "Google Calendar".

### Kanban

Turns markdown checklists into kanban boards with drag-and-drop lanes. Not required for the assistant, but the vault uses kanban for project management.

**Install:** `obsidian://show-plugin?id=obsidian-kanban` or search "Kanban".

### Excalidraw

Whiteboard-style diagramming. The vault stores diagrams in `excalidraw/` and references them in knowledge notes.

**Install:** `obsidian://show-plugin?id=obsidian-excalidraw-plugin` or search "Excalidraw".

## Quick Install Links

Open these in Obsidian (Cmd+Click or paste into browser):

- `obsidian://show-plugin?id=dataview`
- `obsidian://show-plugin?id=obsidian-charts`
- `obsidian://show-plugin?id=templater-obsidian`
- `obsidian://show-plugin?id=obsidian-git`
- `obsidian://show-plugin?id=calendar`
- `obsidian://show-plugin?id=google-calendar`
- `obsidian://show-plugin?id=obsidian-kanban`
- `obsidian://show-plugin?id=obsidian-excalidraw-plugin`
