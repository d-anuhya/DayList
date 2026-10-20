# DayList

A small frosted-glass to-do widget for the macOS desktop.

- Type in **Add a task** and press Return.
- Click a task to check it off. Click again to undo.
- A task you haven't finished keeps showing up each day. On its **2nd day** it turns **orange**, and on its **3rd day** it turns **red** ("Day 3 · finish today").
- **Daily tasks:** click the ⟳ button in the add field before pressing Return, or right-click an existing task and choose **Repeat Daily**. They come back unchecked every morning. Skip one for a day and it turns orange ("Missed yesterday"). Skip it two days in a row and it turns red.
- Right-click a task to **Move to Today** / **Reset Missed Days** (restarts the count) or **Delete** it. You can also hover over it and click ×.
- Finished tasks stay visible (crossed out) until midnight, then disappear.
- Drag the widget from anywhere to move it. Drag its edges to resize it.

**Calendar and week view**
- Today's remaining calendar events show above your tasks. DayList reads them from the Mac's Calendar app, so add Google under System Settings → Internet Accounts and allow DayList when it asks for calendar access.
- Click the calendar button in the widget (or menu bar → **Show Week…**) for a timeline of the week: events as blocks, finished tasks as ticks at the time you did them, and a summary of what you got done (total vs last week, best day, carried-over tasks cleared, longest daily streak, hours booked).
- Every finished task is logged in `history.json`, kept for 180 days, so the week view keeps tasks you've since deleted.

The menu bar icon (✓ plus the number of tasks left) lets you:
- show or hide the widget
- choose where it sits: on the desktop behind windows, like a normal window, or always on top
- turn on **Open at Login**

## Build

```bash
./build.sh
cp -R build/DayList.app /Applications/
open /Applications/DayList.app
```

Tasks are saved in `~/Library/Application Support/DayList/tasks.json`.

For the full guide (updating, colour rules, troubleshooting, backups, uninstalling), see [GUIDE.md](GUIDE.md).
