# Phase 3: Home Shell & Live Refresh - Pattern Map

**Mapped:** 2026-10-08
**Files analyzed:** 2 (both modified in place — no new-file layer in this project)
**Analogs found:** 2 / 2

> **Project shape note (read first).** This repo has no `src/controllers|services|components` tree. Everything is two files: `Akari.ps1` (single-file host: all logic, state, runspaces) and `UI/MainWindow.xaml` (single-window view). The planner's `files_modified` is exactly those two. There is therefore **no cross-file analog to copy from** — every "analog" is *intrapart*: a sibling construct already living in the same file.
>
> The single most important pattern for this phase is **"copy the exact idiom that is already there, one construct at a time."** Each new element below names its sibling and the exact line range to read before writing.
>
> **Tracked-source check (verified):** `git ls-files -- Akari.ps1 UI/MainWindow.xaml` → both returned. Both are git-tracked source. No gitignored mirror is referenced anywhere in this document.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Akari.ps1` (modified) | host / page controller + background-job engine + UI-thread renderer | request-response (nav/search) + event-driven (tick completion) + streaming (log queue) + CRUD-read (CIM spec query) | Intrapart siblings: `Show-Page` (451), `Invoke-Code` + tick (480-530), sidebar `foreach` (567), `New-Row` (382) | exact (same file, same constructs) |
| `UI/MainWindow.xaml` (modified) | view / static page markup | declarative (one-way resource + visibility binding) | Intrapart siblings: `Tuner` `Border` (209-210), `SvcTuner` `Border` (259-260), `Page`/`Heading` (205-206), `Rows` (281), `Nav` (173) | exact (same file, same token set) |

**No external analog exists and none is needed.** Both files are the entire application surface; the "closest existing analog" for every new construct is a construct in the *same* file that already does the same kind of job. The table in `## Pattern Assignments` maps each *construct* (not file) to its sibling.

### Construct-level classification (what the planner actually plans)

| New construct | Lives in | Role | Data Flow | Sibling in same file |
|---------------|----------|------|-----------|----------------------|
| `$script:Cat = 'Home'` default | `Akari.ps1` | config/state | — | `$script:Cat = 'Windows'` (`Akari.ps1:34`) |
| `$script:SpecJob` / `$script:SpecPending` | `Akari.ps1` | state | — | `$script:Job` / `$script:Busy` (`Akari.ps1:35-36`) |
| `Start-SpecRead` function | `Akari.ps1` | service (background job spawn) | async read | `Invoke-Code` (`Akari.ps1:480-502`) — same runspace construction, **minus** the busy guard / `Set-Busy` / log lines |
| `Update-Home` function | `Akari.ps1` | renderer (UI thread) | transform (hashtable → WPF tree) | `New-Row` (`Akari.ps1:382-430`) — programmatic `Border`/`TextBlock` construction + `FindResource` brush lookup |
| `New-FailedSpecs` function | `Akari.ps1` | model factory | transform | `$result = @{...}` init inside `Get-Specs` (`Akari.ps1:133-140`) |
| `$HostIdentityFunc` here-string | `Akari.ps1` | model (spec query) | CRUD-read (CIM) | `$GetSpecsFunc = @'` (`Akari.ps1:103`) + the Motherboard block (`Akari.ps1:326-339`) |
| `Show-Page` Home branch | `Akari.ps1` | controller | request-response | Existing `Show-Page` visibility toggles (`Akari.ps1:461-463`) and empty-state guard (`Akari.ps1:469-474`) |
| Spec-completion tick block | `Akari.ps1` | event handler | event-driven | Existing `$script:Job` completion block (`Akari.ps1:509-528`) |
| `'Home'` nav item + divider | `Akari.ps1` + XAML | controller + view | request-response | Sidebar `foreach` (`Akari.ps1:567-572`) |
| `Set-Variable` shortcut additions | `Akari.ps1` | config | — | Existing list (`Akari.ps1:361`) |
| Static `Home` panel (`Home`/`HomeHeader`/`HostName`/`HostSub`/`Cards`) | `UI/MainWindow.xaml` | view | declarative | `Tuner`/`SvcTuner` `Border` blocks (`UI/MainWindow.xaml:209-210`, `259-260`) |
| Card `Border` (240px) markup | `UI/MainWindow.xaml` (or `Update-Home`) | view | declarative | `Tuner` Border attributes (`UI/MainWindow.xaml:209-210`) and `New-Row`'s inline XAML (`Akari.ps1:410-428`) |

---

## Pattern Assignments

### `Akari.ps1` — default category and new script state

**Analog:** `Akari.ps1:34-38` (the existing `$script:` state block). **Match:** exact — this is where every new `$script:` variable belongs, right next to its sibling.

**State block** (lines 32-38) — the verbatim anchor, with the four changes this phase needs marked:
```powershell
$script:Tweaks = [System.Collections.Generic.List[object]]::new()
$script:RowCache   = @{}
$script:Cat    = 'Windows'          # D-14: becomes 'Home'
$script:Busy   = $false
$script:Job    = $null              # sibling slot: do NOT reuse for specs
$script:Queue  = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:SpecData = $null            # add: $script:SpecJob = $null; $script:SpecPending = $false
```

**Precedent to copy for the new slot:** `$script:Job = $null` is one associative hashtable slot (`Akari.ps1:496`, `:500`, `:524`). The spec read must get a **separate** slot, never this one (RESEARCH Pitfall 7).

---

### `Akari.ps1` — `Start-SpecRead` (second background channel)

**Analog:** `Invoke-Code`, `Akari.ps1:480-502`. **Match:** role-match, deliberate divergence. Copy the runspace construction *exactly*; copy **none** of the three guards.

**The three lines NOT to copy** (lines 480-483) — the reason a new function exists:
```powershell
function Invoke-Code([string]$code, [string]$label, $meta = $null, [string]$ResultVar = $null) {
    if ($script:Busy) { return }
    Set-Busy $true
    Add-Log $label
```

**The PS 5.1 runspace construction to copy verbatim** (lines 493-496):
```powershell
        # ps 5.1 cannot bind the generic BeginInvoke overload with $null input, pass an empty completed collection
        $inputCollection = [System.Management.Automation.PSDataCollection[object]]::new()
        $inputCollection.Complete()
        $script:Job = @{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke($inputCollection, $resultCollection); Label = $label; Meta = $meta; ResultVar = $ResultVar; ResultCollection = $resultCollection }
```
and the runspace open/create preamble (lines 484-488):
```powershell
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('LogQueue', $script:Queue)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
```
> Note: `Start-SpecRead` does **not** need `$rs.SessionStateProxy.SetVariable('LogQueue', ...)` — `Get-Specs` contains no `Write-Log` call (verified, `Akari.ps1:103-357`). Keep it only if the read code ever logs from inside the runspace. The UI-SPEC requires exactly one log line on failure, written from the tick (UI thread), not from the runspace.

**`Set-Busy`** (line 478) — the panel-disable that D-08/D-10 forbid; never call it from the spec path:
```powershell
function Set-Busy([bool]$b) { $script:Busy = $b; $Page.IsEnabled = -not $b }
```

---

### `Akari.ps1` — spec-completion block inside the 150 ms tick

**Analog:** the existing `$script:Job` block, `Akari.ps1:504-530`. **Match:** exact — the new block is a structural sibling of the block already there.

**The tick, verbatim** (lines 504-530). Read this whole range before writing the new block; the new block becomes a sibling *above* the `$j = $script:Job` check (RESEARCH Pitfall 11: spec block first, so the tweak block's `Show-Page` on line 527 re-renders Home from already-updated `$script:SpecData`):
```powershell
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $m = $null
    while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
    $j = $script:Job
    if ($j -and $j.Handle.IsCompleted) {
        try {
            if ($j.ResultVar) {
                [void]$j.Ps.EndInvoke($j.Handle)
                # output lands in the caller-supplied collection, endinvoke returns nothing
                $result = $j.ResultCollection
                if ($result -and $result.Count -gt 0) { $script:SpecData = $result[$result.Count - 1] } else { $script:SpecData = $null }
            } else { [void]$j.Ps.EndInvoke($j.Handle) }
        } catch { Add-Log "Error: $($_.Exception.Message)" }
        foreach ($err in $j.Ps.Streams.Error) { Add-Log "Error: $($err.ToString())" }
        while ($script:Queue.TryDequeue([ref]$m)) { Add-Log $m }
        $j.Ps.Dispose(); $j.Rs.Dispose()
        if ($j.Meta) { $script:State[$j.Meta.Id] = ($j.Meta.Kind -eq 'Apply'); Save-State }
        Add-Log "Done: $($j.Label)"
        $script:Job = $null
        Set-Busy $false
        Read-Svc
        Show-Page
    }
})
$timer.Start()
```

**Sub-patterns lifted from this range for the new block:**

| Pattern | Source lines | Shape |
|---------|--------------|-------|
| Completion predicate | 509-510 | `$j = $script:Job` / `if ($j -and $j.Handle.IsCompleted) {` |
| Empty-completed-input `BeginInvoke` | 493-496 | see above |
| `EndInvoke` in try/catch | 512-518 | `try { [void]$j.Ps.EndInvoke($j.Handle) } catch { Add-Log "Error: $($_.Exception.Message)" }` |
| Error-stream drain | 519 | `foreach ($err in $j.Ps.Streams.Error) { Add-Log "Error: $($err.ToString())" }` |
| Dispose pair | 521 | `$j.Ps.Dispose(); $j.Rs.Dispose()` |
| The "Done" line to NOT copy | 523 | `Add-Log "Done: $($j.Label)"` — D-07 silence |
| Post-job re-render | 527 | `Show-Page` — the D-16 loop risk if the spec path ever calls it |
| D-09 drain point | after 527 | the tweak block ends with `Show-Page`; `if ($script:SpecPending) { Start-SpecRead }` goes on the line after |

**The D-09 drain insertion point, verbatim** (lines 525-528), showing exactly where the drain goes:
```powershell
        Set-Busy $false
        Read-Svc
        Show-Page
        # <- if ($script:SpecPending) { Start-SpecRead }   (D-09 deferred read, runs here, once)
    }
```

---

### `Akari.ps1` — `Show-Page` Home branch

**Analog:** `Show-Page`, `Akari.ps1:451-475`. **Match:** exact — the function is edited in place; the new branch mirrors the existing Tuner visibility pattern and the existing empty-state guard.

**Head of the function** (lines 451-463) — the visibility idiom the Home branch copies (`Visibility = if (...) { 'Visible' } else { 'Collapsed' }`, assigned twice for the paired panels):
```powershell
function Show-Page {
    $q = $Search.Text.Trim()
    $Rows.Children.Clear()
    if ($q) {
        $Heading.Text = "Results for `"$q`""
        $list = @($script:Tweaks | Where-Object { "$($_.Name) $($_.Description)" -like "*$q*" })
    } else {
        $Heading.Text = $script:Cat
        $list = @($script:Tweaks | Where-Object { $_.Category -eq $script:Cat })
    }
    $adv = (-not $q -and $script:Cat -eq 'Advanced')
    $Tuner.Visibility = if ($adv) { 'Visible' } else { 'Collapsed' }
    $SvcTuner.Visibility = $Tuner.Visibility
```
**The condition shape to copy for Home:** `$home = (-not $q -and $script:Cat -eq 'Home')` — literally the same shape as `$adv` on line 461, and it already encodes the Pitfall-8 rule (search-active ⇒ not Home).

**The empty-state guard that must be extended** (lines 469-474) — gain `-and -not $home`:
```powershell
    if (-not $list.Count -and -not $adv) {
        $msg = [Windows.Controls.TextBlock]::new()
        $msg.Text = if ($q) { 'No scripts match.' } else { 'Nothing here yet.' }
        $msg.Foreground = $window.FindResource('Mu')
        [void]$Rows.Children.Add($msg)
    }
```
Precedent for why this matters: with `$script:Cat = 'Home'`, `$list` is empty (grep over `Tweaks/` for `Category = 'Home'` → zero matches) and `$adv` is `$false`, so Home renders **"Nothing here yet."** today.

**Where the Home panel sits in the render order:** the `foreach ($t in $list)` loop (lines 464-468) already no-ops for Home, so the new branch needs no interference there. Add the panel toggle next to lines 461-463.

---

### `Akari.ps1` — `Update-Home` / card renderer

**Analog:** `New-Row`, `Akari.ps1:382-430`. **Match:** exact — same job (build a visual on the UI thread from data), same `FindResource` idiom.

**The `FindResource` brush idiom** (lines 443-448) — copy this verbatim for card brushes:
```powershell
    $dot.Fill = if ($s -eq $true) { $window.FindResource('Inv') } else { [Windows.Media.Brushes]::Transparent }
    $dot.Opacity = if ($null -eq $s) { 0.35 } else { 1 }
    $row.FindName('Opt').Style = $window.FindResource($(if ($s -eq $true) { 'BtnP' } else { 'Btn' }))
    $row.FindName('Def').Style = $window.FindResource('Btn')
```
Note `Opacity` on a per-element basis (line 446) — the dimming precedent for D-06/Pitfall-10.

**The theme-token map** (`New-Row`, line 384) — the existing `Risk → brush key` table; the card renderer follows the same "single lookup, no new brushes" rule:
```powershell
    $riskKey = @{ Safe = 'Mu'; Caution = 'Warn'; Advanced = 'Bad' }[$t.Risk]
```

**The XAML-escaping safety pattern** (line 383) — ASVS V5. Either escape interpolated strings this way, or (recommended) set `.Text` on a `TextBlock` object instead of interpolating into XAML:
```powershell
    $e = { param($s) [Security.SecurityElement]::Escape([string]$s) }
```

**The XAML-in-a-here-string alternative** (lines 410-429) — the `Tuner`-look card markup pattern, if the planner chooses to build each card as parsed XAML rather than .NET objects:
```powershell
    $xaml = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Background="{DynamicResource S1}" BorderBrush="{DynamicResource Bd}" BorderThickness="1" CornerRadius="5" Padding="12,9" Margin="0,0,0,6">
  <StackPanel>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="22"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
```
(then `[Windows.Markup.XamlReader]::Parse($xaml)` on line 429). Either route is acceptable; the `.Text`-on-`TextBlock` route is preferred because it removes the injection surface entirely.

**The label/value `Grid` + `Grid.SetColumn` precedent** (lines 414-415, 423) — what the UI-SPEC's `72 | *` card rows copy:
```powershell
    <Grid.ColumnDefinitions><ColumnDefinition Width="22"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
```
```powershell
    <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">$btns</StackPanel>
```

**Invariant-culture formatting precedent** (`Akari.ps1:345`) — the only existing invariant-format call in the repo; the card renderer must use this form for every numeric field (RESEARCH Pitfall 1):
```powershell
            if ($bios.ReleaseDate) { $biosDate = $bios.ReleaseDate.ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); $mbSuccess++ }
```

---

### `Akari.ps1` — `$HostIdentityFunc` here-string

**Analog:** the `$GetSpecsFunc` here-string + Motherboard block, `Akari.ps1:103`, `326-339`. **Match:** exact — same declaration idiom, same CIM query shape, same filler test.

**The here-string declaration anchor** (line 103) — a single-quoted here-string (no interpolation), which is why `$GetSpecsFunc` can be concatenated into read code:
```powershell
$GetSpecsFunc = @'
function Test-SmbiosValue {
```

**The filler test to reuse for D-12** (lines 104-130) — do not write a second filler list:
```powershell
function Test-SmbiosValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    # common smbios placeholder strings
    $fillers = @(
        'To Be Filled By O.E.M.',
        'Default string',
        'None',
        'N/A',
        'Not Specified',
        'Not Available',
        'System Product Name',
        'System Manufacturer',
        'System Version',
        'System Serial Number',
        'Base Board Version',
        'Base Board Product',
        'Base Board Manufacturer',
        'BIOS Version',
        'BIOS Date',
        'x.x',
        '0'
    )
    $trimmed = $Value.Trim()
    if ($fillers -contains $trimmed) { return $false }
    return $true
}
```

**The CIM read + tolerant-fallback idiom** (lines 326-339) — the exact shape `Get-HostIdentity` copies (default to the `'Not available'` sentinel, try/catch swallow, `.Trim()`, filler-test before accepting):
```powershell
    # --- Motherboard / BIOS ---
    $mbManufacturer = 'Not available'
    $mbProduct = 'Not available'
    $biosVersion = 'Not available'
    $biosDate = 'Not available'
    $mbFields = 4
    $mbSuccess = 0
    try {
        $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        if ($board) {
            if (Test-SmbiosValue $board.Manufacturer) { $mbManufacturer = $board.Manufacturer.Trim(); $mbSuccess++ }
            if (Test-SmbiosValue $board.Product) { $mbProduct = $board.Product.Trim(); $mbSuccess++ }
        }
    } catch { }
```
Note the empty-catch swallow (`} catch { }`) — the codebase's standard tolerant read (AGENTS.md §Error Handling). Also note `$biosDate`'s formatting on line 345 is the invariant-culture precedent cited above.

**The six-group result contract** (lines 132-140) — the shape `New-FailedSpecs` must reproduce exactly (the Phase 2 verify command asserts the sorted key set):
```powershell
    $result = @{
        CPU = @{ _Status = 'OK' }
        RAM = @{ _Status = 'OK' }
        Windows = @{ _Status = 'OK' }
        GPU = @{ _Status = 'OK'; Adapters = @() }
        Disk = @{ _Status = 'OK'; Volumes = @() }
        Motherboard = @{ _Status = 'OK' }
    }
```

---

### `Akari.ps1` — sidebar `Home` item + divider

**Analog:** the sidebar builder + nav handler, `Akari.ps1:567-578`. **Match:** exact.

**Sidebar builder** (lines 567-572) — prepend `'Home'` to the list; the divider `Border` is added after the Home item in the same loop body:
```powershell
foreach ($c in 'Check', 'Refresh', 'Setup', 'Installers', 'Graphics', 'Windows', 'Hardware', 'Advanced') {
    $rb = [Windows.Controls.RadioButton]::new()
    $rb.Content = $c; $rb.Tag = $c; $rb.GroupName = 'nav'
    $rb.Style = $window.FindResource('Nav')
    [void]$Nav.Children.Add($rb)
}
```

**Nav handler** (lines 573-578) — unchanged. This is the single choke point where `$script:Cat` is set; it funnels every Home appearance (launch, nav click, search clear) into `Show-Page`:
```powershell
$Nav.AddHandler([Windows.Controls.Primitives.ToggleButton]::CheckedEvent, [Windows.RoutedEventHandler] {
    param($s, $ev)
    $script:Cat = [string]$ev.OriginalSource.Tag
    if ($Search.Text) { $Search.Text = '' }
    Show-Page
})
$Search.Add_TextChanged({ Show-Page })
```

**Launch selection** (lines 650-654) — already generic; works for `'Home'` with zero change once line 34 flips:
```powershell
$window.Add_Loaded({
    ($Nav.Children | Where-Object { $_.Tag -eq $script:Cat } | Select-Object -First 1).IsChecked = $true
    Add-Log 'Ready.'
    $script:Busy = $false
})
```
Caution (RESEARCH Pitfall 5): assigning `IsChecked = $true` raises `Checked` **synchronously**, so `Show-Page` (and any new `Start-SpecRead`) runs *inside* `Add_Loaded` — every function it calls must be defined **above** line 650.

---

### `Akari.ps1` — `Set-Variable` shortcut list

**Analog:** `Akari.ps1:361`. **Match:** exact — a one-line edit, append four names.

**The list, verbatim** (line 361):
```powershell
foreach ($n in 'Nav', 'Search', 'Heading', 'Tuner', 'SvcTuner', 'SvcCur', 'Rows', 'Page', 'Log', 'Hex', 'Dec', 'Logo') { Set-Variable $n $window.FindName($n) }
```
Becomes: `… 'Page', 'Log', 'Hex', 'Dec', 'Logo', 'Home', 'HostName', 'HostSub', 'Cards') …`. Every name must already exist as an `x:Name` in `UI/MainWindow.xaml` or `FindName` returns `$null` and the shortcut is silently `$null` — which is why the XAML edit is the enabling dependency.

---

### `UI/MainWindow.xaml` — static Home panel + card chrome

**Analog:** the `Tuner` / `SvcTuner` `Border` blocks, `UI/MainWindow.xaml:209-210` and `259-260`. **Match:** exact — same token set, same "collapsed-by-default, shown by code" idiom.

**Ink theme tokens** (lines 9-18) — the closed set. `Home` may use only `S1` (card bg), `Bd` (border/divider), `Tx` (values/headline/hostname), `Mu` (titles/labels/`Loading…`/`Not available`). `Warn`/`Bad` are Phase 4:
```xml
    <!-- Ink tokens. Paper later = same keys, different colors. -->
    <SolidColorBrush x:Key="Bg" Color="#0A0A0A"/>
    <SolidColorBrush x:Key="S1" Color="#141414"/>
    <SolidColorBrush x:Key="S2" Color="#1C1C1C"/>
    <SolidColorBrush x:Key="Bd" Color="#2A2A2A"/>
    <SolidColorBrush x:Key="Tx" Color="#F5F5F5"/>
    <SolidColorBrush x:Key="Mu" Color="#8A8A8A"/>
    <SolidColorBrush x:Key="Inv" Color="#F5F5F5"/>
    <SolidColorBrush x:Key="InvT" Color="#0A0A0A"/>
    <SolidColorBrush x:Key="Warn" Color="#D9A441"/>
    <SolidColorBrush x:Key="Bad" Color="#E5645A"/>
```

**The `Page` host + `Heading`** (lines 205-206) — the insertion point for the new `Home` StackPanel, and the element that collapses while Home shows:
```xml
        <StackPanel x:Name="Page" Margin="16,14">
          <TextBlock x:Name="Heading" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,10"/>
```
`Page` is a single-child-per-line StackPanel inside a `ScrollViewer` with `VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"` (line 204) — a `WrapPanel` card host fits without any scroll change (vertical only, so a growing Disk card scrolls correctly).

**The card-surface attributes to copy** (lines 209-210) — this is the exact look the UI-SPEC D-05 mandates:
```xml
          <!-- Win32PrioritySeparation tuner (Advanced page) -->
          <Border x:Name="Tuner" Visibility="Collapsed" Background="{DynamicResource S1}" BorderBrush="{DynamicResource Bd}"
                  BorderThickness="1" CornerRadius="5" Padding="14,12" Margin="0,0,0,10">
```
Card variation per the UI-SPEC: `CornerRadius="5"` (same), `Padding="16,12"`, `Margin="0,0,8,8"`, `Width="240"`, **no `Height`** (WrapPanel stretches the row to the tallest card).

**The paired-Border visibility idiom** (lines 209-210, 259-260) — `Visibility="Collapsed"` in markup, flipped by `Akari.ps1` (lines 461-463). `Home` follows it:
```xml
          <!-- SvcHost split threshold tuner (Advanced page) -->
          <Border x:Name="SvcTuner" Visibility="Collapsed" Background="{DynamicResource S1}" BorderBrush="{DynamicResource Bd}"
                  BorderThickness="1" CornerRadius="5" Padding="14,12" Margin="0,0,0,10">
```

**The `DockPanel Margin="0,14,0,0"` header-row idiom** (line 244) — what `HomeHeader` copies (right side reserved for the Phase 4 copy button):
```xml
              <DockPanel Margin="0,14,0,0">
```
`HomeHeader` uses `Margin="0,0,0,16"` instead, per the UI-SPEC spacing scale (`lg`).

**The `Rows` container** (line 281) — unchanged; stays empty on Home:
```xml
          <StackPanel x:Name="Rows"/>
```

**The `Nav` host** (line 173) — the sidebar container the `Home` RadioButton and the `Bd` divider are added to (from `Akari.ps1:567`):
```xml
        <StackPanel x:Name="Nav"/>
```

---

## Shared Patterns

### Authentication / Authorization
**None.** No authentication or authorization surface exists in this project — it is a single-user elevated desktop tool (RESEARCH Security Domain, ASVS V2/V3/V4: not applicable). No pattern to apply.

### Theme brush access
**Source:** `Akari.ps1:445-448`, `472` + `UI/MainWindow.xaml:9-18`
**Apply to:** every Home visual (cards, dividers, header, `Loading…`, `Not available`)
- XAML: `{DynamicResource Tx}` / `{DynamicResource Mu}` / `{DynamicResource S1}` / `{DynamicResource Bd}`.
- Code: `$window.FindResource('Tx')` etc. — never `[Windows.Media.Brushes]::White`, never a hex literal.
- Closed set: `S1`, `Bd`, `Tx`, `Mu` only. `Warn` / `Bad` / `InvT` are reserved.

### Error handling
**Source:** `Akari.ps1:511-518` (tick catch), `656-662` (UI-thread guard), `28` (startup trap)
**Apply to:** `Start-SpecRead`, `Update-Home`, the new tick block
```powershell
        } catch { Add-Log "Error: $($_.Exception.Message)" }
```
```powershell
$window.Dispatcher.Add_UnhandledException({
    param($s, $ev)
    $ev.Handled = $true
    Write-ErrLog "UI error: $($ev.Exception.Message)"
    Add-Log "Error: $($ev.Exception.Message)"
    Set-Busy $false
})
```
Rules: never let an exception reach the user as a modal (only `Akari.ps1` chrome and `Confirm-Run` may show a `MessageBox`); the spec path writes **exactly one** `Add-Log` line on failure (D-07 / UI-SPEC E7); never set `$ErrorActionPreference = 'Stop'` or `Set-StrictMode`.

### Logging
**Source:** `Akari.ps1:376-379` (`Add-Log`)
**Apply to:** spec-read failure path only
```powershell
function Add-Log([string]$m) {
    $Log.AppendText(("[{0}] {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $m))
    $Log.ScrollToEnd()
}
```
D-07: a successful refresh logs nothing. Copy is fixed by the UI-SPEC Copywriting Contract: `Specs: Read failed ({msg}). Showing last known values.` / `… Switch to another page and back to Home to try again.`

### Validation
**No input is validated** — Home is read-only. The one relevant rule is ASVS V5: never interpolate an untrusted spec string into XAML. Either `[Security.SecurityElement]::Escape` (`Akari.ps1:383`) or set `.Text` on a constructed `TextBlock` (preferred).

### Background execution / cross-thread bridging
**Source:** `Akari.ps1:504-530` (the 150 ms `DispatcherTimer`)
**Apply to:** the spec read's completion
- One timer, two independent `IsCompleted` checks. Never a second timer, never `Dispatcher.Invoke`, never `Start-Job` / `Task.Run` / `RunspacePool`.
- The tick is the only cross-thread bridge; all WPF construction happens on the UI thread inside `Update-Home`.
- `BeginInvoke` **must** receive the empty completed `PSDataCollection` (`Akari.ps1:493-496`) — passing `$null` throws on PS 5.1 (RESEARCH Pitfall 12).

### Numeric formatting
**Source:** `Akari.ps1:345`
**Apply to:** every numeric spec field
```powershell
$biosDate = $bios.ReleaseDate.ToUniversalTime().ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
```
Never use the `-f` operator for spec numbers (current-culture decimal comma is live on this host). Type-guard first: the `'Not available'` sentinel is a `[string]` and `[string]` has no `ToString(string, IFormatProvider)` overload — `'Not available'.ToString('0.00', $ci)` throws.

### State management
**Source:** `Akari.ps1:32-38`
- All shared mutable state is `$script:` scope in the single-file host.
- New: `$script:SpecJob` (own slot, never `$script:Job`), `$script:SpecPending` (D-09 flag), and the existing `$script:SpecData` (`Akari.ps1:38`, written only at `Akari.ps1:516` today).
- One-flight guard `if ($script:SpecJob) { return }` at the top of `Start-SpecRead` — required because one Home click can produce two `Show-Page` calls (RESEARCH Pitfall 4).

---

## No Analog Found

Nothing. Both files under change have intrapart analogs for every construct (see `## File Classification`). There is no "planner should use RESEARCH.md patterns instead" file in this phase.

Two cross-cutting items are also already solved in-repo rather than needing external patterns:
- SMBIOS filler detection → `Test-SmbiosValue` (`Akari.ps1:104-130`), explicitly marked for reuse in CONTEXT.md.
- Off-UI-thread execution → the existing `Invoke-Code` + tick (`Akari.ps1:480-530`), copied with the busy guard and log lines deliberately removed.

---

## Metadata

**Analog search scope:** repo-wide file inventory (`Akari.ps1`, `IWR.ps1`, `AllowScripts.cmd`, `UI/MainWindow.xaml`, `Tweaks/*.ps1` ×8, `1 Check/` … `8 Advanced/` legacy console scripts, `.planning/codebase/*` maps). This is a two-file application, so the search resolved to intrapart siblings in both files rather than cross-file analogs.

**Files scanned:** `Akari.ps1` (664 lines, read in full across non-overlapping ranges: 1-120, 121-190, 320-343, 340-479, 476-664); `UI/MainWindow.xaml` (292 lines, read in full across non-overlapping ranges: 1-100, 155-189, 193-292); `03-CONTEXT.md`, `03-RESEARCH.md`, `03-UI-SPEC.md`; `AGENTS.md` (project conventions, loaded via project context).

**Constructs with extracted excerpts:** 12 (see the construct-level table in `## File Classification`).

**Pattern extraction date:** 2026-10-08
**Tracked-source verification:** `git ls-files -- Akari.ps1 UI/MainWindow.xaml` → both tracked. No gitignored install/runtime mirror paths emitted.

**Verify commands the planner should carry into PLAN.md** (both from RESEARCH.md Validation Architecture; the first must keep passing):

*Parse + six-group contract (regression gate — do not break `Get-Specs`):*
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '$e=$null;$t=[System.Management.Automation.Language.Parser]::ParseFile("$PWD\Akari.ps1",[ref]$null,[ref]$e);if($e.Count){"FAIL: Akari.ps1 parse errors";exit 1};$s=$t.Find({param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -match "function Get-Specs"},$true);if(-not $s){"FAIL: Get-Specs here-string not found";exit 1};. ([scriptblock]::Create($s.Value));$r=Get-Specs;$g=($r.Keys|Sort-Object) -join ",";if($g -cne "CPU,Disk,GPU,Motherboard,RAM,Windows"){"FAIL: groups=$g";exit 1};"PASS live: groups=$g"'
```

*XAML names + `Akari.ps1` parse (new gate for this phase):*
```powershell
$e=$null
[void][System.Management.Automation.Language.Parser]::ParseFile("$PWD\Akari.ps1",[ref]$null,[ref]$e)
if ($e.Count) { "FAIL: Akari.ps1 parse errors"; exit 1 }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
$w = [Windows.Markup.XamlReader]::Parse((Get-Content "$PWD\UI\MainWindow.xaml" -Raw))
foreach ($n in 'Home','HostName','HostSub','Cards') {
  if (-not $w.FindName($n)) { "FAIL: missing x:Name=$n"; exit 1 }
}
"PASS: Akari.ps1 parses and MainWindow.xaml exposes Home/HostName/HostSub/Cards"
```
