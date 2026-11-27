{
  description = "Agent2API provider plugins for NixOS, packaged with a managed/mutable plugin-sync module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [ "x86_64-linux" ];
      forAll =
        f:
        lib.genAttrs systems (
          system:
          f system (
            import nixpkgs {
              inherit system;
              # Agent2API's license is MIT plus a non-commercial notice.
              config.allowUnfree = true;
            }
          )
        );
    in
    {
      packages = forAll (
        system: pkgs:
        let
          plugins = import ./pkgs { inherit pkgs; };
          server = pkgs.callPackage ./pkgs/agent2api-server.nix { };
          allPlugins = lib.attrValues plugins;
          standalone = import ./lib/mk-standalone.nix { inherit pkgs; };
        in
        plugins
        // {
          agent2api-server = server;
          agent2api-desktop = pkgs.callPackage ./pkgs/agent2api-desktop.nix { };

          # Self-contained launchers: `nix run .#agent2api_managed`. They use
          # the packaged server and every provider pack, and need no systemd.
          agent2api_managed = standalone {
            package = server;
            plugins = allPlugins;
            mode = "managed";
          };
          agent2api_mutable = standalone {
            package = server;
            plugins = allPlugins;
            mode = "mutable";
          };

          default = plugins.agent2api-web-providers;
        }
        // import ./lib/update.nix { inherit pkgs; }
      );

      overlays.default = final: import ./pkgs { pkgs = final; };

      nixosModules.default = import ./modules/default.nix;

      checks = forAll (system: pkgs: import ./checks { inherit pkgs; });
    };
}
