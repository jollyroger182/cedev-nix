{
  description = "A TI-84 Plus CE program";

  inputs.cedev-nix.url = "github:jollyroger182/cedev-nix";
  # Follow cedev-nix's nixpkgs, not the other way around: its clangd is a
  # long LLVM build, and building it against a different nixpkgs means
  # building it again.
  inputs.nixpkgs.follows = "cedev-nix/nixpkgs";

  outputs = { self, nixpkgs, cedev-nix }:
    let
      forAllSystems = nixpkgs.lib.genAttrs (builtins.attrNames cedev-nix.packages);
    in
    {
      # `nix build -o .toolchain` provides the paths compile_flags.txt and
      # .vscode/settings.json point at.
      packages = forAllSystems (system: {
        default = cedev-nix.packages.${system}.toolchain;
      });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ cedev-nix.devShells.${system}.default ];
            packages = [ ];
          };
        });
    };
}
