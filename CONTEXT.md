# XSpoon

XSpoon lets a person capture a control in an app and assign a shortcut that works while that app is in front.

## Language

**Target app**:
The app whose control the person wants to use. Opening XSpoon does not make XSpoon the target app.
_Avoid_: Current app when referring to a saved capture

**Control**:
A button, menu option, or text field that a person can interact with inside the target app.
_Avoid_: Parameter, generic container

**Inspection**:
Looking at the control under the pointer without performing its action.
_Avoid_: Capture when nothing has been selected yet

**Capture**:
A record of a selected control, its target app, and the evidence needed to find it again.
_Avoid_: Screenshot, click coordinates alone

**Saved shortcut**:
A key combination paired with a captured control and the action to perform on it, scoped to its target app.
_Avoid_: Preset when only a key combination has been chosen

**Replay**:
Performing a saved shortcut's action on its control while its target app is in front.
_Avoid_: Success when only the shortcut was registered

**Modifier preset**:
A named combination of modifier keys that can be paired with a trigger key.
_Avoid_: Action, capture

**App registry**:
The collection of target apps and their saved actions, organized with each app as
the parent of its actions.
_Avoid_: Separate shortcut list when referring to saved actions

**Action review**:
The recorded confidence and usability of a saved action: verified, unverified,
blocked, or needing recapture. Saving an action does not verify its replay.
_Avoid_: Working merely because a record exists

**Inherited command**:
An existing app command listed for reference whose behavior is managed outside
the captured-action workflow.
_Avoid_: Captured action when no captured control exists
