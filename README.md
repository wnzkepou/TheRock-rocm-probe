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
  and its `rocm_v7_1` backend. It identified the RX 6800, offloaded all 29
  model layers to the GPU, and reported the model resident in VRAM. Its
  Vulkan backend was disabled for that test to avoid the NVIDIA T600. The
  provided installer leaves GPU discovery automatic and does not select a
  GPU index or bus ID.
- The project-local Python 3.14 environment installed
  `requirements.txt`; `pip check`, dependency imports, pytest, and Meson
  verification passed.
- The selected Windows-applicable components, including the successful
  rocDecode/AMD Mesa, FFTW3, and host-BLAS probes, were built and installed to
  `C:\Workspaces\TheRock-rocm-probe\install`.
- A second Windows 11 Pro installation on an RX 6700 XT completed for
  `gfx1030;gfx1031`; the installed `rocminfo.exe` reported the card as
  `gfx1031`. ccache 4.14.2 was used with up to eight aggregate build workers.
- Ollama 0.40.16's ROCm DLLs were staged and hash-verified. Its API responded,
  and with `HSA_OVERRIDE_GFX_VERSION=10.3.0` it enumerated the RX 6700 XT as
  `gfx1030`. This was a device-detection check only; no model inference was
  performed.

The build targets `gfx1030;gfx1031`. It does not include every TheRock feature:
the probe results are summarized here:

| Area | Result |
| --- | --- |
| CV / RPP | Configure rejected: RPP is not supported on Windows. |
| Media | `rocDecode` and its AMD Mesa dependency built successfully. |
| Emulation | `rocJITsu` and Mirage were each rejected as unsupported on Windows. |
| WSL | The WSL ROCDXG subproject requires a Linux/WSL build environment; it did not build from native Windows. |
| Other optional components | `FFTW3` and host BLAS built successfully. Other individually tested Windows-unsupported components were rejected during configure. |

See the detailed notes for per-flag results, methodology, and the exact build
configuration.

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
2. Set up Python dependencies and fetch the remaining pinned sources:

   ```powershell
   py -3 -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install -r requirements.txt
   python build_tools\fetch_sources.py
   ```

   The environment used for this probe is Python 3.14. The `.venv` directory
   is local to the checkout and is ignored by Git.
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

To install Ollama and configure its ROCm backend to use this TheRock install,
run `build_tools\install_ollama_rocm.ps1` from PowerShell. The script sets the
required backend environment variables without selecting a GPU or bus ID; see
the detailed notes for its backup and restart behavior.
For Ollama 0.40.16 on an RX 6700 XT, the backend initially dropped `gfx1031`
because its rocBLAS target map did not include it. The user-level
`HSA_OVERRIDE_GFX_VERSION=10.3.0` setting allowed Ollama to enumerate the card
as `gfx1030`; this compatibility override affects other HSA applications too.
It has not been validated with model inference.

To clone the official Ollama Git repository and build Ollama plus its
`rocm_v7_1` backend against this TheRock install, run
`build_tools\build_ollama_rocm.ps1`. It uses a separate clean checkout and
does not modify an existing Ollama installation.

## Disclaimer

This fork modifies experimental Windows ROCr/HIP behavior. Results depend on
the GPU, Windows version, driver, compiler, and application. The Ollama result
was verified on one machine; `rocminfo` detection alone does not establish
that a different application or system will work. Back up existing runtime
files and test in an isolated installation before replacing any ROCm DLLs.
