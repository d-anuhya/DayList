# DayList — User Guide

A small frosted-glass to-do widget that sits on your Mac's desktop.

---

## 1. Install

From the project folder (`~/Documents/Personal Projects/ToDo List App`):

```bash
./build.sh
cp -R build/DayList.app /Applications/
open /Applications/DayList.app
```

Then click the **✓ icon in the menu bar** → **Open at Login** so it starts every time you log in.

> DayList has no Dock icon. You control it from the ✓ icon in the menu bar at the top of the screen.

---

## 2. Update after making changes

Whenever the code changes, rebuild and replace the copy in Applications:

1. Quit DayList: menu bar ✓ → **Quit DayList**
2. Run:
   ```bash
   cd "$HOME/Documents/Personal Projects/ToDo List App"
   ./build.sh
   rm -rf /Applications/DayList.app
   cp -R build/DayList.app /Applications/
   open /Applications/DayList.app
   ```

Your tasks are kept. They're stored separately from the app (see section 7).

---

## 3. Everyday use

| To… | Do this |
|---|---|
| Add a task | Type in **Add a task** at the bottom, press **Return** |
| Add a daily task | Click the **⟳** button (it turns green), type, press **Return** |
| Check off a task | Click anywhere on the task |
| Undo a check | Click it again |
| Delete a task | Hover over it and click **×**, or right-click → **Delete** |
| Make an existing task daily | Right-click → **Repeat Daily** |
| Stop a task repeating | Right-click → **Stop Repeating Daily** |
| Clear an orange/red warning | Right-click → **Move to Today** (one-off) or **Reset Missed Days** (daily) |
| Move the widget | Drag it from any empty spot |
| Resize the widget | Drag its edges |

The ring at the top right shows how many of today's tasks are done (e.g. `3/5`).
Finished tasks stay crossed out until midnight, then disappear.

---

## 4. Colour rules

### One-off tasks
An unfinished task carries over to the next day until you check it off.

| Day | Colour | Label |
|---|---|---|
| Day 1 (the day you added it) | Normal | — |
| Day 2 | 🟠 Orange | "Day 2 · carried over" |
| Day 3 and later | 🔴 Red | "Day 3 · finish today" |

### Daily tasks (⟳)
They come back unchecked every morning. The colour shows how many days in a row you've skipped:

| Situation | Colour | Label |
|---|---|---|
| Done yesterday (or just added) | Normal | — |
| Skipped yesterday | 🟠 Orange | "Missed yesterday" |
| Skipped 2+ days in a row | 🔴 Red | "Missed 2 days · do it today" |

Red tasks show at the top, then orange, then the rest.
When anything is red, a banner says **"N tasks have to be done today."**

---

## 5. Menu bar options

Click the **✓** icon (the number next to it is how many tasks are left today):

- **Show / Hide Widget**
- **Position**
  - *On the Desktop (behind windows)*: acts like a desktop widget (default)
  - *Like a Normal Window*
  - *Always on Top*: floats over everything
- **Open at Login**
- **Quit DayList**

---

## 6. Troubleshooting

| Problem | Fix |
|---|---|
| Widget disappeared | Menu bar ✓ → **Show Widget**. If it's in "On the Desktop" mode, it may be hidden behind other windows. Press **F11** / swipe to show the desktop, or switch to *Always on Top* |
| No ✓ icon in the menu bar | DayList isn't running: `open /Applications/DayList.app` |
| "Open at Login" shows an error | Make sure the app is in **/Applications**, then try again. Or add it manually: System Settings → General → Login Items → **+** |
| Widget is off-screen or in a strange spot | Quit DayList, run `defaults delete com.anuhya.daylist`, then reopen it. It goes back to the top-right corner |
| Build fails with an `@State` macro error | Use `State(initialValue:)` instead of `@State` in the code. The `@State` macro only works with full Xcode, not the Command Line Tools |

---

## 7. Where your data lives

All tasks are saved locally (nothing goes online) in:

```
~/Library/Application Support/DayList/tasks.json
```

**Back up your tasks:**
```bash
cp "$HOME/Library/Application Support/DayList/tasks.json" ~/Desktop/daylist-backup.json
```

**Restore a backup** (quit DayList first):
```bash
cp ~/Desktop/daylist-backup.json "$HOME/Library/Application Support/DayList/tasks.json"
```

Finished one-off tasks are removed from the file automatically after 30 days. Daily tasks are never removed automatically.

---

## 8. Uninstall

1. Menu bar ✓ → turn off **Open at Login**, then **Quit DayList**
2. Run:
   ```bash
   rm -rf /Applications/DayList.app
   rm -rf "$HOME/Library/Application Support/DayList"
   defaults delete com.anuhya.daylist
   ```

---

## 9. Project files

| File | What it is |
|---|---|
| `Sources/App.swift` | Widget window, menu bar icon, Open at Login |
| `Sources/TaskStore.swift` | Task list, saving, day counting, colour rules |
| `Sources/Views.swift` | How the widget looks (layout, colours, checkboxes) |
| `Info.plist` | App name and settings (hides the Dock icon) |
| `build.sh` | Builds `build/DayList.app` |
| `GUIDE.md` | This guide |
