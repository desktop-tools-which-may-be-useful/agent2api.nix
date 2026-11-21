{ pkgs }:
let
  lib = pkgs.lib;
  specs = import ./plugins.nix;
  mk = import ../lib/mk-plugin.nix { inherit pkgs; };
in
lib.listToAttrs (
  map (spec: lib.nameValuePair spec.id (mk spec)) specs
)
