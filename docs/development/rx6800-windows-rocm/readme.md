# Windows ROCm build for the RX 6800

This repository is a personal, experimental TheRock fork documenting a
Windows ROCm build for the AMD Radeon RX 6800. The fork contains changes to
TheRock and its `rocm-systems` and `rocm-libraries` submodules; it is not an
official AMD release or a general Windows installation guide. For general
TheRock setup, see the upstream
[Windows support guide](https://github.com/ROCm/TheRock/blob/main/docs/development/windows_support.md).

## Get this fork

Clone the feature branch with its pinned submodules:

```powershell
git clone --recurse-submodules --branch rx6800-windows-rocm `
  https://github.com/wnzkepou/TheRock-rocm-probe.git
cd TheRock-rocm-probe
```

The parent repository pins the matching commits from the personal
[`rocm-systems`](https://github.com/wnzkepou/rocm-systems/tree/rx6800-windows-rocm)
and
[`rocm-libraries`](https://github.com/wnzkepou/rocm-libraries/tree/rx6800-windows-rocm)
forks. Keep those pins when building this branch; updating submodules
independently may drop the compatibility fixes.

## Status

- TheRock feature branch: `rx6800-windows-rocm`.
- The `rocm-systems` and `rocm-libraries` submodules are pinned to the
  corresponding commits on their matching feature branches.
- Host: Windows 10, Visual Studio 2022, AMD Radeon RX 6800.
- GPU target list: `gfx1030;gfx1031` (the RX 6800 reports `gfx1030`).
- The Windows-applicable components selected in this build were built and
  installed with `ninja install-rocm`.
- Install tree: `C:\Workspaces\TheRock-rocm-probe\install`.
- The installed `bin\rocminfo.exe` successfully enumerates the RX 6800 as
  `gfx1030`. The install includes ROCr/HIP and the enabled math, ML, compiler,
  and supporting components.
- Ollama was separately verified using the locally built ROCr/HIP runtime:
  it identified the RX 6800, offloaded all 29 model layers, and reported the
  model in VRAM. That validation required staging runtime DLLs in Ollama's
  ROCm backend and using its versioned backend name, `rocm_v7_1`.
- For the initial manual Ollama validation, the persistent user environment
  included `GPU_ENABLE_PAL=0`, `OLLAMA_LLM_LIBRARY=rocm_v7_1`,
  `OLLAMA_VULKAN=0`, and `HIP_VISIBLE_DEVICES=0`; `GGML_VK_VISIBLE_DEVICES`
  was removed. After restarting the desktop app, it detected the RX 6800 as
  its ROCm `gfx1030` device, not the NVIDIA T600. A `qwen2.5-coder:7b`
  prompt succeeded, `ollama ps` reported `100% GPU`, and the runner logged
  all 29 model layers offloaded. The provided installer now clears
  device-index filters and leaves runtime GPU discovery automatic.
- A project-local `.venv` was set up with Python 3.14.10 and the repository's
  `requirements.txt`. Dependency consistency (`pip check`), key imports,
  pytest, and Meson were verified successfully. Create an equivalent
  environment from the repository root with:

  ```powershell
  py -3 -m venv .venv
  .\.venv\Scripts\Activate.ps1
  python -m pip install -r requirements.txt
  ```
- Component probes added `rocDecode`/AMD Mesa, FFTW3, and host BLAS to the
  active build configuration. Their artifact targets built successfully, and
  the updated configuration was installed to the prefix above with
  `ninja install-rocm`. After installation, `rocminfo.exe` continued to report
  the RX 6800 as `gfx1030`.

This is not every TheRock feature. RPP, emulation, WSL ROCDXG, and several
optional components were rejected or could not be built on the native Windows
host. See the probe results below. Inspect `build-rocm1030\CMakeCache.txt` for
the current selection.

## Component probe results

Each optional feature below was enabled individually, with previously
successful optional features retained. Configure-time rejections were turned
back off before the next probe. The successful media and optional artifacts
were built for the existing `gfx1030;gfx1031` configuration.

| Area | Flags / component | Result |
| --- | --- | --- |
| CV | `THEROCK_ENABLE_CV_LIBS=ON`, `THEROCK_ENABLE_RPP=ON` | Configure rejected: `RPP is not supported on Windows`. Both remain off. |
| Media | `THEROCK_ENABLE_MEDIA_LIBS=ON`, `THEROCK_ENABLE_ROCDECODE=ON`, `THEROCK_ENABLE_SYSDEPS_AMD_MESA=ON` | `artifact-rocdecode` and the AMD Mesa sysdep built successfully and were installed. Mesa source was initialized at the parent-pinned submodule commit after the first build attempt found it absent. These options remain on. |
| Emulation | `THEROCK_ENABLE_ROCJITSU=ON`; Mirage enabled separately | Each configure was rejected with “not supported on Windows.” Both remain off. |
| WSL | `THEROCK_ENABLE_WSL=ON`, `THEROCK_ENABLE_WSL_ROCDXG=ON` | Top-level configure passed, but the nested `wsl-rocdxg` configure rejected the native Windows host and requires Linux/WSL. The available Alpine WSL distro lacked the required build tools, so no artifact was built. Both options remain off. |
| Optional success | `THEROCK_ENABLE_FFTW3=ON` | `artifact-fftw3` built and installed successfully; remains on. |
| Optional success | `THEROCK_ENABLE_HOST_BLAS=ON` | `artifact-host-blas` (OpenBLAS) built and installed successfully; remains on. |
| Optional rejection | `CORE_HRR`, `CORE_AMDSMI`, `ELFIO`, `HOST_SUITE_SPARSE` | Each was enabled individually and rejected during feature validation as unsupported on Windows. They remain off. |
| Optional rejection | `AQLPROFILE`, `PROFILER_HUB`, `ROCPROFILER_COMPUTE`, `ROCPROFSYS`, `ROCPROFV3`, `ROCR_DEBUG_AGENT`, `ROCGDB` | Each was enabled individually and rejected during feature validation as unsupported on Windows. They remain off. |
| Optional rejection | `HIPFILE`, `RCCL`, `RDC`, `ROCSHMEM`, `ROCJPEG`, `ROCJITSU_HOTSWAP` | Each was enabled individually and rejected during feature validation as unsupported on Windows. They remain off. |

Names in the optional rejection rows are suffixes of the corresponding
`THEROCK_ENABLE_<name>` CMake cache flags.
For the optional rejection rows, the CMake feature validator reported the
specific feature as “not supported on Windows”; no build target was attempted.
The test-only switches (`CORE_KFDTESTS`, `CORE_RUNTIME_TESTS`,
`ROCR_DEBUG_AGENT_TESTS`, and `ROCPROFILER_SYSTEMS_EXAMPLES`) were not probed:
they add tests/examples rather than standalone runtime components. Linux system
dependency switches and the `HOST_MATH` umbrella option were also left alone;
they are dependencies or aggregate selections, not independent components.
The supported math, compiler, and ML components from the original build were
not re-probed as part of this optional-component pass.

## Important local source changes

The feature branch contains Windows/shared-HSA compatibility changes. These
are experimental fork changes and are not implied to be upstream TheRock
behavior:

- `core/CMakeLists.txt` selects shared ROCr and disables PAL when
  `THEROCK_FLAG_HSA_WINDOWS_SHARED_RUNTIME` is enabled.
- `rocm-systems/projects/clr/rocclr/cmake/ROCclrHSA.cmake` makes the Windows
  HIP runtime load the shared ROCr runtime.
- `rocm-systems/projects/clr/rocclr/cmake/FindAMD_HSA_LOADER.cmake` guards
  against duplicate registration of the `oclelf` subdirectory.
- `rocm-systems/projects/clr/rocclr/device/rocm/rocdevice.cpp` routes the
  shader-engine query through ROCclr's dynamic HSA wrapper.
- `rocm-systems/projects/rocr-runtime/runtime/hsa-runtime/hsacore.dll.def`
  exports `hsa_amd_agent_set_attribute`, which ROCclr needs.
- `rocm-libraries/projects/hipblaslt/device-library/matrix-transform/matrix_transform.h`
  has a Windows/HIP vector-access compatibility fix.

The source changes are committed in this fork and its two modified submodules.
The generated `build-rocm1030` tree contains local build files and workarounds;
only its portable initial-cache options file is committed.

## Approximate build process

1. Follow TheRock's upstream Windows support guide and install the required
   Visual Studio 2022 C++ tools, Windows SDK, CMake, Ninja, Git, and Python.
2. Clone this fork using the instructions above. Initialize its Python
   environment, install `requirements.txt`, and fetch the remaining pinned
   sources using `build_tools\fetch_sources.py`. The `rocm-systems` and
   `rocm-libraries` submodules are already pinned by the parent checkout; the
   math-library build also uses the pinned `libhipcxx` source.
3. Configure a Ninja build with the committed
   `build-rocm1030\WindowsRX6800BuildOptions.cmake` initial-cache file. It
   records the `gfx1030;gfx1031` targets, the experimental shared-HSA option,
   and the tested Windows feature selection. Set the install prefix for the
   local machine:

   ```powershell
   cmake -S . -B build-rocm1030 -G Ninja `
     -C build-rocm1030/WindowsRX6800BuildOptions.cmake `
     -DCMAKE_INSTALL_PREFIX=C:/path/to/install
   ```

   `THEROCK_ENABLE_ALL=ON` alone does not override existing feature choices
   in an already-configured build tree. The generated `CMakeCache.txt`,
   manifests, binaries, and local workaround edits are intentionally not
   committed.
4. Build and install from a Visual Studio developer environment. For this
   checkout, the equivalent command is:

   ```cmd
   set "PATH=C:\Program Files\Git\usr\bin;%PATH%"
   call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64
   cd /d C:\Workspaces\TheRock-rocm-probe\build-rocm1030
   ninja install-rocm -j 2
   ```

   Put Git's Unix tools on `PATH` before `VsDevCmd.bat`; the developer command
   script resets portions of `PATH`. Git's `patch.exe` was needed by a
   dependency patch during this build.
5. If CMake regenerates a nested project's `CMake`/Ninja rules and a Windows
   resource compile (`rc.exe`) fails on preprocessor line markers, inspect
   that project's generated `CMakeFiles\rules.ninja`. For the affected
   `cmake_llvm_rc` rule, adding `-P` to the Clang preprocessing phase
   (`-x c -E -P -- $in ++`) resolved the failure here. This is a generated
   build-file workaround: it may need to be reapplied after reconfiguration.
6. Confirm the installed runtime can see the GPU:

   ```powershell
   $env:PATH = 'C:\Workspaces\TheRock-rocm-probe\install\bin;' + $env:PATH
   $env:ROCM_PATH = 'C:\Workspaces\TheRock-rocm-probe\install'
   & 'C:\Workspaces\TheRock-rocm-probe\install\bin\rocminfo.exe'
   ```

   Look for the AMD Radeon RX 6800 and `gfx1030` in the HSA agents.

## Build-specific caveats

- To build Ollama itself against this TheRock installation, run
  `build_tools\build_ollama_rocm.ps1`. The script clones
  `https://github.com/ollama/ollama.git` with its submodules into a separate
  `ollama-rocm-build\source` checkout beside the TheRock repository, then
  builds Ollama and the `rocm_v7_1` backend with the TheRock HIP compiler and
  `CMAKE_PREFIX_PATH` set to `install`. `AMDGPU_TARGETS=gfx1030` controls
  compiled kernel support only; it does not select a runtime GPU or bus ID.
  The resulting `ollama.exe` is in the source checkout, and the backend
  payload plus required TheRock runtime DLLs are in
  `ollama-rocm-build\build-rocm\lib\ollama\rocm_v7_1`. This is a local build
  output; the script does not replace the installed Ollama application.
  Existing source checkouts must use the official Ollama origin and have a
  clean worktree. Pass `-UpdateSource` to fast-forward a clean local branch.
  Ollama source fetching and the first native build require network access.
- To install Ollama and stage the runtime built by TheRock, run
  `build_tools\install_ollama_rocm.ps1` from a PowerShell prompt at the
  repository root. It installs Ollama with `winget` only if Ollama is absent,
  verifies the versioned `rocm_v7_1` backend, backs up any differing runtime
  DLLs, then stages `amdhip64_7.dll`, `amd_comgr.dll`, `hsa-runtime64.dll`,
  `rocm_kpack.dll`, `hiprtc0718.dll`, and `hiprtc-builtins0718.dll` from
  `install\bin`. It persists
  `GPU_ENABLE_PAL=0`, `OLLAMA_LLM_LIBRARY=rocm_v7_1`, and `OLLAMA_VULKAN=0`
  for the current user. It clears existing HIP/ROCr/Vulkan device-index
  filters; it does not set a GPU index or PCI/bus address, so ROCm performs
  automatic device discovery. Exit Ollama before running the script, then
  reopen it afterward so the new environment takes effect. Use `-WhatIf` to
  preview the actions without changing files or environment variables.
- HIPBLASLt in the pinned source does not support `gfx1030`; TheRock falls back
  to `gfx1100`. Do not force its target list to `gfx1030`/`gfx1031`. Three
  HIPBLASLt test/benchmark executables containing only `gfx1100` code had to
  be omitted from this local `gfx1030` test-artifact package so the artifact
  splitter could finish. This did not change the library source or the
  runtime installation.
- Windows' long-path limit affected generated HIPBLASLt/TensileLite paths.
  Short junctions (`C:\tr` and `C:\h`) and edits to generated Ninja paths
  were used locally. Keep those junctions while generated build manifests
  depend on them; do not edit the canonical source/glob manifests to shorten
  paths.
- Re-running the full install after changing the feature selection required
  setting `LIBHIPCXX_COPY_TO_BUILD=OFF` in the generated top-level Ninja
  command. This uses libhipcxx's documented no-copy mode and avoids a Windows
  symlink-copy error during reconfiguration; the source checkout was not
  changed.
- External-project builds should use TheRock's sanitized environment. If
  running a nested build manually, unset any machine-wide `ROCM_PATH`,
  `ROCM_DIR`, `HIP_PATH`, and `HIP_DIR` so installed ROCm headers do not leak
  into this build.
- Ollama validation is separate from installing TheRock. Do not copy
  replacement DLLs into another ROCm installation without first backing up
  the originals and testing with an isolated setup. The successful Ollama
  result above was measured on this machine with the `rocm_v7_1` backend; it
  is not inferred from `rocminfo` alone and does not guarantee compatibility
  on other Windows systems or Ollama versions.
