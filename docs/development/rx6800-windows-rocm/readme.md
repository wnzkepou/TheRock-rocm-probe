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

This is not every TheRock feature. CV, media, emulation, and WSL were disabled;
other optional components are disabled according to the build cache. Inspect
`build-rocm1030\CMakeCache.txt` for the exact selection.

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
The `build-rocm1030` directory contains generated build files and local
workarounds; it is not a clean, portable build recipe.

## Approximate build process

1. Follow TheRock's upstream Windows support guide and install the required
   Visual Studio 2022 C++ tools, Windows SDK, CMake, Ninja, Git, and Python.
2. Clone this fork using the instructions above. Initialize its Python
   environment, install `requirements.txt`, and fetch the remaining pinned
   sources using `build_tools\fetch_sources.py`. The `rocm-systems` and
   `rocm-libraries` submodules are already pinned by the parent checkout; the
   math-library build also uses the pinned `libhipcxx` source.
3. Configure a Ninja build for `gfx1030;gfx1031`, enable the experimental
   `THEROCK_FLAG_HSA_WINDOWS_SHARED_RUNTIME` option, and select the desired
   Windows-capable feature groups. In this checkout those settings are in
   `build-rocm1030\CMakeCache.txt`. `THEROCK_ENABLE_ALL=ON` alone did not
   replace previously cached feature-group choices; check the cache rather
   than assuming every option was enabled.
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
