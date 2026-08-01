# Unreal validation fixtures

Real captured engine output used to version-verify the `unreal-observe` log grammar.

- `parrot-ue5.6.1-cooklog.txt` — a real `BuildCookRun -build -cook` of ParrotGameSample on
  **UE 5.6.1** (linux/amd64, dev-slim image), captured 2026-07-10 on the Windows build host.
  Green build (0 err/0 warn, 1006 pkgs cooked). This is the evidence behind the
  grammar corrections logged in `../LEARNINGS.md`: real 5.6 uses **ZenServer** DDC +
  `FShaderJobCache stats` (no `DDC Hit Rate` line), and a `Cooked packages N … Total T`
  cook tally.

- `parrot-ue5.8-vs-5.6-mismatch.txt` — the 5.6→5.8 **mismatch money-shot**: a UE **5.8**
  engine (`dev-slim-5.8`) run `-skipcompile` against ParrotGameSample's **5.6-built** binaries
  (BuildId `43139311`), captured 2026-07-11. Note the *real* headless presentation — the 5.8
  engine **silently drops** the 5.6 module and reports a misleading `LogPluginManager: … module
  'CommonStartupLoadingScreen' could not be found … consider disabling the plugin` (ExitCode
  25), **not** the interactive "different engine version — rebuild?" prompt. This is the
  evidence behind the new §8 "headless mismatch" signature row.

- `parrot-ue5.6-build-fail-rulesError.txt` — a real **build-failure** log (matched UE 5.6),
  captured 2026-07-12 by deliberately typo'ing a module dep in `Parrot.Build.cs`
  (`EnhancedInput` → `EnhancedInputs`). Real UBT output: `Could not find definition for module
  'EnhancedInputs', (referenced via Target -> Parrot.Build.cs)` · `Result: Failed (RulesError)`
  · `ExitCode=8`. Evidence for §8's "Could not find definition for module" row (fix the
  typo/name — do NOT add it as a dependency) and the exit-code decode (`8`=RulesError).

- `butterup-ue5.8-cooklog.txt` — a real matched **UE 5.8** build+cook of Butter Up
  (`//sample-game`), captured 2026-07-13. Green (`Packages Cooked: 496/503`, 0 err/0 warn).
  Confirms the §5/§7 grammar (ZenServer / `FShaderJobCache` / `Cooked packages N … Total T`)
  holds on 5.8 as well as 5.6 — i.e. the fixes are version-general, not 5.6-specific.
