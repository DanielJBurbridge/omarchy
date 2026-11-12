# Alpha follow-ups

Not part of spec 02. These are the optional notes from [review 5870531064](https://github.com/DanielJBurbridge/omarchy/pull/36#pullrequestreview-5870531064) on PR #36.

- L14. Number the backstop rungs after a failed 5 s lock. That lock leaves 7 s before the 3 s margin: SIGTERM at 5 s, SIGKILL at 7 s, `terminate-session` at 9 s, decision by 12 s. Spec 02 still says only that the rungs are compressed into what remains.
- L15. The broker re-checks `EndDesktop` itself (handheld variant, `desktop-lock` `on`, no physical keyboard, a desktop session active, marker absent) and does nothing otherwise. The 30 s notice draws above the idle screensaver, which Quickshell starts at 150 s.
