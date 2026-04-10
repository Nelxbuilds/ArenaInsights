# Bug Tracker

Add bugs here as you find them. Format: one entry per bug, newest at the top.

---

<!--
Template:
## BUG-N — Short description
**Story**: X-Y
**Status**: open | in progress | fixed
**Found**: how/where you found it
**Description**: what's wrong
**Fix**: (fill in when resolved)
-->

## BUG-6 — Overlay hard to move
**Story**: 4-1
**Status**: fixed
**Found**: opening overlay
**Description**: I try to drag it and i need to try multiple times until it works
**Fix**: Rows had EnableMouse(true) for tooltips but weren't forwarding drag events, so they consumed clicks before the overlay frame could start dragging. Added RegisterForDrag and OnDragStart/OnDragStop scripts to each row that forward to the overlay frame.

## BUG-5 — Overlay way too wide
**Story**: 4-1
**Status**: fixed
**Found**: opening overlay
**Description**: the overlay is way too wide. It shouldn't take up that much space. look at resources-to-delete/002-overlay-example.png that is way smaller and works too
**Fix**: Reduced excessive padding in the dynamic width calculation — cut name-to-rating gap from 20px to 8px and removed a redundant 20px spacer before the right edge, saving 36px total.

## BUG-4 — Account name is not updated in export
**Story**: 3-4
**Status**: open
**Found**: Change account name and do new export
**Description**: While I do understand that most likely account name would be updated with a new game being recorded. If there is no account name set for records and in settings a new account name is being added. Wouldn't it make sense to add this account name to those empty entries. Do not overwrite existing account names.
**Fix**: (fill in when resolved)

## BUG-3 — Active tab overlaps nearly with other tabs
**Story**: 3-1
**Status**: open
**Found**: Open with /nxr and just click on a tab
**Description**: I have given you a demo with bug-3.png
**Fix**: (fill in when resolved)

## BUG-2 — Cannot close export after clicking on export once
**Story**: 3-4
**Status**: fixed
**Found**: Just clicking Export in the Import/Export.
**Description**: It grows that text field so much, that you can't seen anything anymore. and even closing the windows didn't restore the previous state. Only /reload helped
**Fix**: Wrapped both export and import EditBoxes in ScrollFrames (UIPanelScrollFrameTemplate) so they stay at fixed 120px height instead of auto-growing with content.

## BUG-1 — /nxr doesn't open on first enter
**Story**: 2-2
**Status**: fixed
**Found**: human checkpoint for this story
**Description**: first command execution of /nxr does nothing. No LUA error just nothing. On second execution the challenges frame is being shown
**Fix**: Frame was shown by default on creation, then the toggle immediately hid it. Added early return after first creation so the frame stays visible.
