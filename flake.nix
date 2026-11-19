{
  description = "The CE C/C++ toolchain for the TI-84 Plus CE, plus a clangd that understands ez80";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = f:
        nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" ]
          (system: f nixpkgs.legacyPackages.${system});

      # The CE C/C++ toolchain, from its prebuilt release. Its tools find the
      # install prefix relative to themselves, so it runs from the store as-is.
      mkCedev = pkgs:
        let
          inherit (pkgs) lib stdenv;
          version = "15.0";
          releases = {
            aarch64-darwin = { asset = "CEdev-macOS-arm.dmg"; hash = "sha256-PMbL5ULKhR+Mn1X7/ArdUSsbjgWFPjPju/HemVH50w4="; };
            x86_64-darwin = { asset = "CEdev-macOS-intel.dmg"; hash = "sha256-Ix2E0a9JwH1Coi454Ivbn5JTilP0/Zv703smULnjkRU="; };
            x86_64-linux = { asset = "CEdev-Linux.tar.gz"; hash = "sha256-hfR5SmF7E0JJqcuooIRBTobhbSpoN3sdcqzjDGNtvfk="; };
          };
          release = releases.${stdenv.hostPlatform.system}
            or (throw "CEdev ${version} has no prebuilt release for ${stdenv.hostPlatform.system}");
        in
        stdenv.mkDerivation {
          pname = "cedev";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://github.com/CE-Programming/toolchain/releases/download/v${version}/${release.asset}";
            inherit (release) hash;
          };

          # The .dmg also carries Finder decorations next to CEdev/.
          sourceRoot = "CEdev";

          nativeBuildInputs = lib.optionals stdenv.isDarwin [ pkgs.undmg ]
            ++ lib.optionals stdenv.isLinux [ pkgs.autoPatchelfHook ];
          buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib ];

          dontConfigure = true;
          dontBuild = true;
          dontStrip = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r . $out/
            runHook postInstall
          '';

          meta = {
            description = "CE C/C++ toolchain for the TI-84 Plus CE";
            homepage = "https://ce-programming.github.io/toolchain/";
            platforms = builtins.attrNames releases;
          };
        };

      # clangd built from the CE Programming LLVM fork. Upstream LLVM has no
      # ez80 target, so a stock clangd rejects --target=ez80 and IntelliSense
      # engines that emulate x86/arm get sizeof(int) wrong (4 instead of 3).
      #
      # Pinned to the commit CEdev v15's ez80-clang reports in --version, so
      # the editor and the compiler agree. Only the frontend is needed: the
      # Z80 TargetInfo lives in clang/lib/Basic, so building the `clangd`
      # target never compiles the Z80 codegen backend or any host backend.
      mkClangd = pkgs: pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "ez80-clangd";
        version = "19.1.0-unstable-2026-04-18";

        src = pkgs.fetchFromGitHub {
          owner = "CE-Programming";
          repo = "llvm-project";
          rev = "ef28e9c54cd1333a6091ab2ffbd315b465fc5090";
          sparseCheckout = [ "cmake" "third-party" "llvm" "clang" "clang-tools-extra" ];
          hash = "sha256-9IHUVwHj+MaNNEhy/6vv5M0cH5pdnXUqrQMpybVPOoc=";
        };

        sourceRoot = "${finalAttrs.src.name}/llvm";

        nativeBuildInputs = with pkgs; [ cmake ninja python3 ];

        cmakeFlags = [
          "-DCMAKE_BUILD_TYPE=Release"
          "-DLLVM_ENABLE_PROJECTS=clang;clang-tools-extra"
          # Same target setup as the fork's CI: no host backends, Z80 only.
          "-DLLVM_TARGETS_TO_BUILD="
          "-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Z80"
          "-DLLVM_DEFAULT_TARGET_TRIPLE=ez80"
          "-DLLVM_ENABLE_ASSERTIONS=OFF"
          # LLVM links are memory-hungry; don't run several at once.
          "-DLLVM_PARALLEL_LINK_JOBS=1"
          "-DLLVM_INCLUDE_TESTS=OFF"
          "-DLLVM_INCLUDE_EXAMPLES=OFF"
          "-DLLVM_INCLUDE_BENCHMARKS=OFF"
          "-DLLVM_INCLUDE_DOCS=OFF"
          "-DCLANG_INCLUDE_TESTS=OFF"
          "-DLLVM_ENABLE_ZLIB=OFF"
          "-DLLVM_ENABLE_ZSTD=OFF"
          "-DLLVM_ENABLE_LIBXML2=OFF"
          "-DLLVM_ENABLE_TERMINFO=OFF"
          # clang-tidy check modules are most of clangd's link; CE code
          # doesn't need them.
          "-DCLANGD_TIDY_CHECKS=OFF"
          "-DCLANGD_BUILD_XPC=OFF"
        ];

        ninjaFlags = [ "clangd" "clang-resource-headers" ];

        # clangd finds its builtin headers at <bin>/../lib/clang/<major>.
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin $out/lib
          cp bin/clangd $out/bin/
          cp -r lib/clang $out/lib/
          runHook postInstall
        '';

        meta = {
          description = "clangd from the CE Programming LLVM fork (ez80 target)";
          homepage = "https://github.com/CE-Programming/llvm-project";
          mainProgram = "clangd";
        };
      });
    in
    {
      packages = forAllSystems (pkgs: rec {
        cedev = mkCedev pkgs;
        clangd = mkClangd pkgs;

        # Stable paths for editor config: `nix build -o .toolchain` gives
        # .toolchain/cedev (headers for compile_flags.txt) and
        # .toolchain/clangd (for clangd.path), and keeps both from being
        # garbage-collected.
        toolchain = pkgs.runCommand "cedev-toolchain" { } ''
          mkdir -p $out
          ln -s ${cedev} $out/cedev
          ln -s ${clangd} $out/clangd
        '';

        default = toolchain;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "cedev";

          packages = with self.packages.${pkgs.stdenv.hostPlatform.system}; [
            cedev
            clangd
          ];

          shellHook = ''
            echo "CEdev $(cedev-config --version), $(clangd --version | head -1)"
          '';
        };
      });

      templates.default = {
        path = ./template;
        description = "A TI-84 Plus CE program with the CE toolchain and ez80 clangd";
        welcomeText = ''
          Next steps:

          ```sh
          direnv allow                # or: nix develop
          nix build -o .toolchain     # editor paths for clangd
          make
          ```

          The first build compiles clangd from source (about 45 minutes).
        '';
      };
    };
}
