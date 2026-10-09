# Detect reads the machine and never falls back to what the user clicked

A Tweak's row shows only what Detect reads from the machine right now: Applied, Not applied, Partly applied or Unknown. We retired the remembered last click (`state.json`), because a remembered click goes stale silently after a Windows update or a manual change, and a confident wrong answer is worse than an honest Unknown. For Tweaks that import an embedded `.reg` payload, Detect is derived from that same payload rather than hand-written, so Apply and Detect cannot drift apart; hand-written Detect from a few representative values was rejected because it reports Applied when part of the bundle has been reset.

## Consequences

- Detect counts only lasting settings that Revert restores (registry values, service start types, power and boot settings, scheduled-task state, optional features); one-shot steps such as removing apps or restarting Explorer are not part of "applied".
- Applied means the machine matches Apply's target, Not applied means it matches Revert's target, anything else is Partly applied; values identical in both targets are ignored.
- Anything a Revert cannot restore is left out of Detect and stated in the Tweak's description instead.
- Detect runs in the background each time a Category page is shown, never on the UI thread.
