{
  description = "Agent2API provider plugins for NixOS, packaged with a managed/mutable plugin-sync module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f system (import nixpkgs { inherit system; }));
    in
    {
      packages = forAll (
        system: pkgs:
        let
          plugins = import ./pkgs { inherit pkgs; };
        in
        plugins // { default = plugins.agent2api-web-providers; }
      );

      overlays.default = final: import ./pkgs { pkgs = final; };

      nixosModules.default = import ./modules/default.nix;

      checks = forAll (system: pkgs: import ./checks { inherit pkgs; });
    };
}
