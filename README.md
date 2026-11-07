# TheRock ROCm on Windows: RX 6800

This personal, experimental fork documents a native Windows ROCm build for the
AMD Radeon RX 6800 (GPU target `gfx1030`). It is based on
[AMD's TheRock](https://github.com/ROCm/TheRock), with companion changes in
the [`rocm-systems`](https://github.com/wnzkepou/rocm-systems/tree/rx6800-windows-rocm)
and
[`rocm-libraries`](https://github.com/wnzkepou/rocm-libraries/tree/rx6800-windows-rocm)
submodules.

> **Scope:** This is a machine-tested research build, not an official AMD
> Windows distribution or a claim that every ROCm feature works on every
> Windows system.

## What has been verified

- TheRock's installed `rocminfo.exe` detects the RX 6800 as `gfx1030`.
- Ollama was tested on this machine with the locally built ROCr/HIP runtime
  and its `rocm_v7_1` backend. Ollama identified the RX 6800, offloaded all
  29 model layers to the GPU, and reported the model resident in VRAM.
- The Windows-applicable components selected for this configuration built
  and installed to `C:\Workspaces\TheRock-rocm-probe\install`.

The build targets `gfx1030;gfx1031`. It does not include every TheRock feature:
CV, media, emulation, and WSL were disabled, as were other optional components.
See the detailed notes for the exact configuration and caveats.

## Get the source

Clone this branch with its pinned submodules:

```powershell
git clone --recurse-submodules --branch rx6800-windows-rocm `
  https://github.com/wnzkepou/TheRock-rocm-probe.git
cd TheRock-rocm-probe
```

The parent repository pins the matching submodule commits. Keep those pins
when building this branch; independently updating either submodule may remove
the compatibility changes.

## Build overview

1. Prepare Windows and Visual Studio 2022 using the
   [upstream TheRock Windows support guide](https://github.com/ROCm/TheRock/blob/main/docs/development/windows_support.md).
2. Set up Python dependencies and fetch the remaining pinned sources with
   `build_tools\fetch_sources.py`.
3. Configure a Ninja build for `gfx1030;gfx1031`, enable the experimental
   `THEROCK_FLAG_HSA_WINDOWS_SHARED_RUNTIME` option, and explicitly select
   the desired Windows-capable feature groups.
4. From a Visual Studio developer command prompt, build and install:

   ```cmd
   cd /d path\to\TheRock-rocm-probe\build-rocm1030
   ninja install-rocm -j 2
   ```

   During the tested build, Git's Unix tools needed to precede other patch
   utilities on `PATH`. Some generated nested Ninja rules also needed a local
   Windows resource-compiler workaround. Long HIPBLASLt/TensileLite paths
   required build-directory-only workarounds. These details are specific to
   the tested checkout and are documented below.
5. Run the installed `bin\rocminfo.exe` and confirm the HSA agent reports
   the RX 6800 and `gfx1030`.

## Detailed status and build notes

See the
[Windows RX 6800 build notes](docs/development/rx6800-windows-rocm/readme.md)
for the tested configuration, experimental source changes, approximate
commands, DLL/driver cautions, and known limitations.

## Disclaimer

This fork modifies experimental Windows ROCr/HIP behavior. Results depend on
the GPU, Windows version, driver, compiler, and application. The Ollama result
was verified on one machine; `rocminfo` detection alone does not establish
that a different application or system will work. Back up existing runtime
files and test in an isolated installation before replacing any ROCm DLLs.
