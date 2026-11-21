# Derive the desired plugin registry from a list of plugin packages.
#
# `packs[].path` is the store path of the unpacked pack (see mk-plugin.nix);
# the sync script links it under `$dataDir/plugins/<id>/<version>` and writes
# the matching `plugins.json`. `providers` is the per-provider enabled map the
# managed mode enforces (derived from pack.json's default_enabled).
{ pkgs }:
{ plugins }:
let
  lib = pkgs.lib;

  packOf =
    p:
    let
      packPath = "${p}";
      manifestPath = "${packPath}/pack.json";
      m = builtins.fromJSON (builtins.readFile manifestPath);
      target = p.passthru.target or "x86_64-unknown-linux-gnu";
      entry = m.entry.${target} or (throw "agent2api plugin ${m.id} has no entry for target ${target}");
    in
    {
      id = m.id;
      version = m.version;
      path = packPath;
      inherit entry;
      providers = lib.listToAttrs (
        map (pr: lib.nameValuePair pr.id (pr.default_enabled or true)) m.providers
      );
      manifest_providers = m.providers;
      sha256 = p.passthru.zipSha256 or "";
    };

  packs = map packOf plugins;
in
{
  inherit packs;
  file = pkgs.writeText "agent2api-plugins-manifest.json" (builtins.toJSON { inherit packs; });
}
