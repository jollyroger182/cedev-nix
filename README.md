# cedev-nix

The [CE C/C++ toolchain](https://ce-programming.github.io/toolchain/) for the TI-84 Plus CE as a Nix flake, plus a `clangd` built from [CE Programming's LLVM fork](https://github.com/CE-Programming/llvm-project) so editors understand the ez80 target.

Why the custom clangd: upstream LLVM has no ez80 target. A stock clangd rejects `--target=ez80`, and VS Code's C/C++ extension emulates x86/arm, so it reports `sizeof(int) == 4` (and `sizeof(int24_t) == 4`) where the calculator has 3.

## New project

```sh
mkdir mygame && cd mygame
nix flake init -t github:jollyroger182/cedev-nix
direnv allow                # or: nix develop
nix build -o .toolchain
make
```

The template includes:

- `flake.nix`: a dev shell with `cedev-config`, `ez80-clang`, `convimg` and friends, and `clangd`
- `compile_flags.txt`: the flags the CEdev makefile passes, so clangd sees what `make` sees
- `.vscode/settings.json`: points the clangd extension at `.toolchain/clangd`, and turns off the C/C++ extension's IntelliSense for the folder
- a starter `makefile` and `src/main.c`

`.toolchain` is a symlink to the toolchain in the Nix store. It gives the editor config stable relative paths, and it is a GC root, so `nix-collect-garbage` keeps the toolchain while the project exists.

## Notes

- The first build compiles clangd from source, which takes about 45 minutes. Later builds and other projects reuse it, as long as they use cedev-nix's nixpkgs.
- Don't override this flake's nixpkgs (`inputs.cedev-nix.inputs.nixpkgs.follows = ...`): a different nixpkgs means a different clangd build. Have your project follow it instead, as the template does (`inputs.nixpkgs.follows = "cedev-nix/nixpkgs"`).
- CEdev comes from the official v15.0 release builds: `aarch64-darwin`, `x86_64-darwin` and `x86_64-linux`. clangd is pinned to the LLVM fork commit that release's `ez80-clang` was built from.
- The Linux package hasn't been tested yet.
