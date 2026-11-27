# Update runner for this repository, modeled after nixpkgs'
# maintainers/scripts/update.nix and nur-packages' helpers/update.nix.
#
# Two kinds of packages live here:
#
#   * agent2api-server / agent2api-desktop carry `passthru.updateScript`
#     (nix-update-script): GitHub-tag based Rust packages, updated by
#     nix-update including src hash and cargoHash.
#   * The 41 provider plugins share one generated file (pkgs/plugins.nix)
#     regenerated from the upstream Agent2plugin index by
#     maintainers/update-plugins.py; they intentionally have no per-package
#     updateScript. `update-plugins` wraps that script.
#
# `update` runs both: nix-update per Rust package, then the plugin refresh.
#
# Usage:
#   nix run .#update                  # everything
#   nix run .#update-server
#   nix run .#update-desktop
#   nix run .#update-plugins          # plugins.nix only
#   nix run .#update-plugins -- --check
{ pkgs }:
let
  lib = pkgs.lib;

  python = pkgs.python3;

  update-plugins = pkgs.writeShellApplication {
    name = "agent2api-update-plugins";
    runtimeInputs = [
      python
      pkgs.cacert
      pkgs.git
    ];
    text = ''
      cd "$(git rev-parse --show-toplevel)"
      exec python3 ${../maintainers/update-plugins.py} "$@"
    '';
    meta.description = "Regenerate pkgs/plugins.nix from the upstream Agent2plugin index";
  };

  # nix-update evaluates `--flake` packages through the store copy reported
  # by `nix flake metadata`. Nix >= 2.35.5 deletes the copy of a dirty tree
  # before the follow-up evaluation can use it (see nur-packages'
  # helpers/nix-update-overlay.nix); evaluate the working tree instead.
  nix-update = pkgs.nix-update.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace nix_update/options.py --replace-fail \
        'return get_flake_store_path(self.import_path)' \
        'return None  # store copy of a dirty tree is deleted before use'
    '';
  });

  mkRustUpdater =
    attr:
    pkgs.writeShellApplication {
      name = "agent2api-update-${attr}";
      runtimeInputs = [
        nix-update
        pkgs.nix
        pkgs.git
        pkgs.cacert
      ];
      text = ''
        cd "$(git rev-parse --show-toplevel)"
        # --use-github-releases: track tagged releases (skips prereleases by
        # default), matching the `tag = "v..."` fetcher in the package.
        exec nix-update --flake --use-github-releases ${lib.escapeShellArg attr} "$@"
      '';
      meta.description = "nix-update wrapper for ${attr}";
    };

  update-server = mkRustUpdater "agent2api-server";
  update-desktop = mkRustUpdater "agent2api-desktop";

  update = pkgs.writeShellApplication {
    name = "agent2api-update";
    runtimeInputs = [
      update-server
      update-desktop
      update-plugins
    ];
    text = ''
      status=0
      agent2api-update-agent2api-server || status=1
      agent2api-update-agent2api-desktop || status=1
      agent2api-update-plugins || status=1
      exit "$status"
    '';
    meta.description = "Update server, desktop and the plugin index";
  };
in
{
  inherit
    update
    update-server
    update-desktop
    update-plugins
    ;
}