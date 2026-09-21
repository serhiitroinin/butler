# Butler — design direction, version 4: "full-bleed"

Version 1 (serif livery) felt like a costume. Version 2 (stock Finder table)
was correct and forgettable. Version 3 (the ledger: manila tabs, a rubber
stamp, pencil marks, a sticky note) was rejected by the owner: "no
skeuomorphism; paper-like minimalistic UI with nice textures." Version 4
replaces it completely. The references in `docs/design-references/`:

- `05-full-bleed.png` — THE PAGE, light. Build this.
- `07-full-bleed-dark.png` — the dark appearance of the same page.
- `09-full-bleed-states.png` — no folders, working, a revised proposal with
  the change request and the agent's reply flat inline, approved with Undo.
- `10-full-bleed-rules-history.png` — the House Rules editor and History.

They are references, not pixel specs: counts, sizes, and copy in them are
illustrative. Everything on screen derives from the real plan.

## The idea in one sentence

Paper is the material of the whole window, not an object inside it: one warm
stock from edge to edge with a fine tooth you can see when you look for it,
ink-coloured type set densely on it, hairlines between regions, and one olive
accent. Nothing imitates a physical thing.

## Rules

1. **One paper tone, full-bleed.** Sidebar, toolbar, content, inspector and
   bottom bar share one stock. Light: content `#F3F0E8`, sidebar a half-step
   darker `#ECE8DE`. Dark: charcoal `#1F1F1D`, sidebar `#1A1A18`, off-white
   ink `#EDE9E1`. No inset sheet, no sheet shadow, no desk. Regions are
   separated by single hairlines only (light `#000000` at 10 %, dark
   `#FFFFFF` at 10 %). Never two hairlines next to each other.
2. **Texture you can see, quietly.** A fine, clean paper tooth across the
   entire window, titlebar included. It is procedural: a tiled noise image
   generated in code at the backing scale (an even tooth averaged so no pixel reads as a speck, light
   weighing more than shade, plus a very soft wide mottle; no fibres, no
   flecks: the first build read as dirty), never a photo. Measured spread
   about 0.7 % of full scale in light and 1.4 % in dark: visible at 1x when you look for
   it, never noisy behind text. Reduce Transparency or Increase Contrast
   drops the grain and leaves the flat stock.
3. **Zero skeuomorphism.** No tabs, stamps, pencil marks, strikethroughs,
   `stet`, margin notes, leader lines, sticky notes, rotation, sheet edges,
   shadows, or stacked sheets. Flat replacements only (see Anatomy).
4. **One accent: muted olive.** Light `#5E6B4E`, dark `#8A9A76`. It marks the
   selected sidebar row, the active segment, checkboxes, progress, and the
   Approve button. Where the accent is a surface under light text in dark
   (sidebar row, segment, buttons) it deepens to `#5A684C`; `#8A9A76` under
   text glares. A Trash destination and an error are a muted red (light
   `#A4483C`, dark `#D0857A`). File icons are the only other colour.
5. **Ink.** Primary ink `#1E1C18` / `#EDE9E1`; secondary at 60 %; tertiary at
   40 %. Excluded rows sit at 45 %, applied rows at 40 %.
6. **Dense and typographic.** SF Pro throughout. SF Mono only for sizes,
   counts, and the rules editor. Title 22 pt semibold; group headers 12 pt
   semibold with a count; rows 22 pt high with 12 pt text; secondary 11 pt;
   tabular numerals. A hairline between groups only, never under every row.
   Target 26–28 file rows visible at 1180 × 760.
7. **Native bones.** `NavigationSplitView`, real toolbar items (segmented
   Proposal · Before · After, the engine menu, search, Organise/Stop),
   `.inspector`, a `Settings` scene, keyboard shortcuts, Quick Look, context
   menus, multi-select. Menus, popovers and Settings stay stock: no paper.
8. **Motion.** System defaults and short cross-fades (120–200 ms). Reduce
   Motion: cross-fades only, no staggering.

## Window anatomy

- **Sidebar** (200 pt, sidebar stock): managed folders with a count badge,
  then House Rules and History, Settings at the foot. The selected row is an
  olive fill. Add with `+`, ⌘O, or a drag from Finder.
- **Toolbar** (same stock as the content, a hairline under it): the segmented
  picker (drawn by the app inside a real toolbar item, because neither
  SwiftUI's nor AppKit's segmented control will colour its active segment in
  a toolbar; accessibility sees a picker), the engine `Menu` ("Claude · Sonnet"), search, Organise (⌘R) or
  Stop (⌘.), and the inspector toggle (⌥⌘I).
- **Header**: the folder name in 22 pt semibold; next to it the **status
  label**, a small flat capsule — Proposed, Working, Approved, Rejected,
  Undone — in a muted tint; next to that, when there is more than one
  revision, a small `Revision 2 of 2` menu that switches the page to an
  older revision (read-only) and back. On the same baseline, at the right
  edge, one 11 pt secondary line: `57 selected · 2 excluded · 19 new
  folders`. (The reference puts it under the title; on the baseline it costs
  no row.)
- **Column heads** on one hairline: a tri-state select-all checkbox · Name ·
  From → To · Kind · Size.
- **Groups**, one per destination folder in the plan's order: a 12 pt
  semibold header with the disclosure chevron, the group's tri-state
  checkbox, the whole path (`Invoices/2024`), the count in parentheses, `new`
  in secondary when the folder will be created, and the size in mono at the
  right. One hairline above each group.
- **Rows** (22 pt): a quiet checkbox tinted olive, the 16 pt file icon, the
  name (a rename reads `report (1).pdf → report-copy-1.pdf`), `Downloads →
  Invoices/2024` in secondary, Kind, Size in mono. Selection is a faint ink
  wash. An **excluded** row dims to 45 % and carries a flat `Excluded`
  capsule at the right edge (the capsule itself is not dimmed). A row that
  changed in the latest revision carries a small flat `rev 2` text mark in
  the same place.
- **Trash group** last; its To column reads `Trash` in the muted red. Its
  rows are excluded by default, so nothing goes to the Trash unless ticked.
- **Conversation**, above the bottom bar, only when a change was asked for:
  a flat block of `You: …` / `Butler: …` lines (the reply is the revision's
  own note; while the engine works the reply reads `Working…`). No bubble,
  no note, no rotation.
- **Bottom bar** (same stock, a hairline above): left, the status line in
  12 pt; middle, `Ask for changes…`; right, Reject and an olive Approve
  (⌘↩ only while the field is empty).
- **Inspector** (⌥⌘I): "Why" for the selected row, the agent's note, and
  problems. A stock form on the same paper.

## The approve moment

Bound to the real applier, never ahead of it:

1. On Approve the status label reads `Working` and the bottom bar shows a
   determinate olive progress line with the current item.
2. As each operation completes its row dims to 40 %; when a group's last
   operation completes the group header gains a small `done`.
3. A failing operation stops the sequence: that row shows the error inline
   in the muted red, the rows after it stay undimmed, and the label returns
   to `Proposed`. The bottom bar repeats the error with what was really
   moved before it and offers Undo alone; nothing can be decided until the
   moved items are back, because the plan no longer matches the folder.
   After Undo the plan is a plain proposal again. History lists the run as
   `Stopped`.
4. When the applier finishes the label turns `Approved` and the bottom bar
   becomes `Tidied · N items` with Undo. Undo turns the label `Undone`.

Reduce Motion: the same changes as cross-fades.

## House Rules and History

- **House Rules**: the title, a one-line subtitle, then a mono 12 pt editor
  with line numbers in a hairline-bordered area; `Saved HH:mm` at the foot
  on the left, `Applies to future proposals` on the right; a Templates menu
  in the toolbar.
- **History**: a flat table — Date, Folder, Status — with 22 pt rows, and
  under a hairline a detail section for the selected run: its totals, its
  engine, its items as `name → destination`, and Undo or Redo.

## States

- No folders: a folder glyph, "A little order starts here.", one secondary
  line, and an olive Add Folder… button, centred on the bare stock.
- No proposal: the header, "No proposal yet.", and Organise.
- Working: the header with the `Working` label, the live activity line, an
  indeterminate olive progress line, "No files moved.", and Stop.
- Search with no match: one secondary line in the list area.

## What to keep

All of `ButlerCore` behaviour and its tests, the sidecar, the launch-argument
page driving, the offline engine, the ⌘↩ safety, the tri-state inclusion
model, and `PlanTable`. The status state machine stays, renamed away from the
stamp. View code the design does not use is deleted.

## Verification

- `swift build` clean, `swift test` green.
- Screenshots at 1180 × 760 in FORCED light and FORCED dark in
  `docs/screenshots/`: no folders, no proposal, working, proposal, rows
  excluded, change request sent, revision 2 with the agent's note, Before,
  After, applying mid-way, applied with Undo, an apply stopped by a locked
  file, History, House Rules, engine menu open, Settings; plus one 2x crop
  of the texture per appearance.
- Density check: count the file rows visible in the proposal screenshot and
  put the number in the README.
- One live Claude (sonnet) turn against `.demo/Downloads` at the end to
  confirm the loop, then Undo (`live-claude.png`).
- Quit everything you launch; `pgrep` clean before you finish.
