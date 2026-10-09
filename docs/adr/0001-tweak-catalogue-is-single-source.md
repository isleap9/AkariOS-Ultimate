# The Tweak catalogue files are the single source of truth

The `Tweaks/*.ps1` files were originally generated from standalone numbered scripts (`1 Check/` … `8 Advanced/`). Those folders were deleted in `d38e5e1` and every Tweak now runs in-app, so we decided `Tweaks/*.ps1` is the only place a Tweak's code lives: new Tweaks are written there directly, and the "GENERATED" headers and the "mirror changes in both sides" rule are retired. We rejected restoring the standalone scripts because keeping two copies of every Tweak doubles maintenance for a launch path the app no longer uses.
