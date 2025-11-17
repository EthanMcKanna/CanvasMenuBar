# CanvasMenuBar

CanvasMenuBar is a native SwiftUI menu bar app that keeps your macOS status bar up to date with Canvas assignments due **today** (based on your local timezone). It polls the Canvas REST API on a schedule, stores your credentials securely in the Keychain, and stays out of the Dock thanks to `LSUIElement`.

## Requirements

- macOS 13.0 Ventura or newer
- Xcode 15 (or newer) with the latest Swift toolchain
- A Canvas account with permission to create an API token

## Getting Started

1. **Create or pick a folder** – this repo already lives in `CanvasMenuBar/`. Open `CanvasMenuBar.xcodeproj` in Xcode.
2. **Build & run** – choose the "CanvasMenuBar" target and hit Run. The app appears as an icon in the right side of the menu bar.
3. **Configure Canvas** – click the menu bar icon → `Settings…`, then pick your preferred **Data Source**:
   - **API Token (full metadata)** – enter your Canvas domain (e.g. `school.instructure.com`) and a personal access token (Canvas → Account → Settings → *New Access Token*). Follow [Canvas' token guide](https://community.canvaslms.com/t5/Canvas-Basics-Guide/How-do-I-obtain-an-API-access-token-for-an-account/ta-p/386) if you need help.
   - **Calendar Feed (no token required)** – choose *Calendar Feed* and paste the iCal URL from Canvas → Calendar → **Calendar Feed**. This works even if your school blocks API-token creation.
4. **Refresh** – the assignments list refreshes immediately, and again on the cadence you set in Settings (default: every 30 minutes). Use the `Refresh` button for on-demand syncs.
5. **Work the list** – use the day navigator (chevrons + the floating `Today` pill) to browse any date. Flip the **All / Assignments / Events** filter, check off assignments you finish, and keep an eye on the progress tracker (you can toggle it off in Settings if you want a minimalist layout).
6. **Menu bar badge** – turn on *Show remaining assignments count* in Settings → **Menu Bar** to see a tiny badge atop the calendar icon. The number always reflects **today’s** remaining assignments, even if you’re previewing future days.

## How it Works

- The app calls `GET /api/v1/calendar_events` with `type=assignment`, `start_date`, and `end_date` set to the current day to pull only due-today assignments. It follows pagination via the Canvas `Link` header and filters the results once more on-device.
- If you switch to the Calendar Feed data source, `ICSAssignmentsService` parses the `.ics` feed, unescapes HTML descriptions, locations, and categories, and still filters everything down to "due today" locally.
- Networking lives in `Networking/CanvasAPI.swift`, which handles ISO-8601 date decoding, pagination, and error translation.
- Credentials are stored outside of `UserDefaults` using the Keychain wrapper in `Services/KeychainService.swift`. A UUID `configurationVersion` is published whenever settings change so `AssignmentsViewModel` knows to refresh.
- `MenuBarExtra` renders the UI. `AssignmentsMenuView` shows the daily list, relative due times, state badges, and (optionally) a completion tracker. `SettingsView` exposes Canvas connection details **plus** toggles for the tracker, menu bar badge, and launch-on-login behavior.
- The app hides its Dock icon by setting `LSUIElement = true` in `Info.plist`, so it behaves like a dedicated menu bar utility.

## Customization Ideas

- Filter by specific courses by filling `contextCodes` inside `CanvasAPI.fetchAssignments`.
- Add reminders/notifications when due dates approach.
- Persist a cache of the last fetch so the menu populates instantly on launch.
- Surface more Canvas metadata (submission scores, attachments, etc.).
- Persist completion history to sync across devices or export to Reminders.
- Add keyboard shortcuts for quick day navigation or filter changes.
- Let the app remember your preferred popover size or theme.

## Canvas Without API Tokens

If your institution disables personal access tokens, use the built-in Calendar Feed option:

1. In Canvas, open **Calendar** and click **Calendar Feed** on the right.
2. Copy the secret iCal (`.ics`) link.
3. In CanvasMenuBar Settings, set **Data Source** to *Calendar Feed* and paste the URL.

The feed includes all assignments/events visible on your calendar, and CanvasMenuBar will filter them down to items due today.

## Troubleshooting

- **401 errors**: usually caused by an expired or revoked token. Delete + re-add in Settings.
- **Empty list**: confirm you're looking at the right Canvas instance and that assignments actually have due dates set for today.
- **Networking**: the status text in the menu will show the error message surfaced by `CanvasAPIError`; check Console logs for richer context if needed.
- **Launch at login** toggle errors: Some enterprise machines block programmatic login items. If you see an error in Settings, manually add the app in **System Settings → General → Login Items**.

Feel free to extend the project or integrate with login items if you want it to launch automatically at login.
