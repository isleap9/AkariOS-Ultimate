# AkariOS-Ultimate

A Windows tweaking tool: a catalogue of reversible system changes a power user can apply, revert and inspect from one window, plus a Home page of live system specs.

## Language

### Catalogue

**Tweak**:
One user-visible system change in the catalogue, identified by a kebab-case id and shown as one row.
_Avoid_: Script, option, setting, fix

**Category**:
A sidebar page that groups Tweaks by purpose (e.g. Windows, Graphics, Advanced).
_Avoid_: Section, tab, folder

**Apply / Revert**:
Apply puts a Tweak's change in place; Revert restores the Windows default.
_Avoid_: Optimize/Default (legacy menu wording), enable/disable, undo

**Detect**:
A read-only probe that reports whether an on/off Tweak is currently applied, by inspecting the machine itself. One-shot actions have no Detect.
_Avoid_: Check (that is a separate, user-triggered diagnostic action), status

**Partly applied**:
The Detect result for a Tweak whose changes are only some of them in place, e.g. after a Windows update reset part of a bundle.
_Avoid_: Mixed, partial, dirty

**Unknown**:
The Detect result when the machine cannot be read (missing service, denied key, timeout). Never shown as applied or not applied.
_Avoid_: Error, N/A

**Installed**:
Whether the program an installer Tweak installs is present on the machine. Distinct from Detect: an installer is never "applied".
_Avoid_: Detected, applied