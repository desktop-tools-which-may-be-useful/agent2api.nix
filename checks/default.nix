{ pkgs }:
let
  lib = pkgs.lib;
  plugins = import ../pkgs { inherit pkgs; };

  # Small representative subset: one native pack (patched ELF) and two wasm
  # packs (the Trae/ZCode providers). All 41 packages are still built by
  # `nix flake check` via the `packages` output.
  sample = [
    plugins.agent2api-web-providers
    plugins.agent2api-wasm-trae
    plugins.agent2api-wasm-zcode
  ];

  nativePlugins = lib.filterAttrs (
    _: p: (p.passthru.target or "") == "x86_64-unknown-linux-gnu"
  ) plugins;

  entryOf =
    p:
    let
      m = builtins.fromJSON (builtins.readFile "${p}/pack.json");
    in
    m.entry.${p.passthru.target};

  manifest = import ../lib/make-manifest.nix { inherit pkgs; } { plugins = sample; };
  syncScript = import ../lib/sync-script.nix { inherit pkgs; };
in
{
  # Native packs must have been autoPatchelf'd to a NixOS interpreter;
  # otherwise the gateway reports exit code 127 at runtime.
  interpreters = pkgs.runCommand "agent2api-check-interpreters" { } ''
    ${lib.concatMapStrings (p: ''
      interp="$(${pkgs.patchelf}/bin/patchelf --print-interpreter ${p}/${entryOf p})"
      case "$interp" in
        /nix/store/*) ;;
        *) echo "unpatched interpreter for ${p}: $interp" >&2; exit 1 ;;
      esac
    '') (lib.attrValues nativePlugins)}
    touch $out
  '';

  # The sync script is the contract between the Nix declaration and the
  # gateway's plugins.json. Guard its layout and both modes' semantics.
  sync = pkgs.runCommand "agent2api-check-sync" {
    nativeBuildInputs = [
      syncScript
      pkgs.jq
    ];
  } ''
    set -euo pipefail
    data=$(mktemp -d)

    agent2api-sync-plugins managed "$data/plugins" ${manifest.file}
    test -f "$data/plugins/plugins.json"
    n=$(jq '.packs | length' "$data/plugins/plugins.json")
    test "$n" -eq ${toString (lib.length sample)} || {
      echo "managed seeded $n packs, expected ${toString (lib.length sample)}" >&2; exit 1;
    }

    # Every declared pack must resolve through plugins/<id>/<version>.
    jq -r '.packs[] | .id + "/" + .version' "$data/plugins/plugins.json" |
      while IFS= read -r p; do
        test -e "$data/plugins/$p" || { echo "missing link $p" >&2; exit 1; }
      done

    # Re-running managed on an unchanged declaration must not rewrite state.
    before=$(sha256sum "$data/plugins/plugins.json")
    agent2api-sync-plugins managed "$data/plugins" ${manifest.file}
    after=$(sha256sum "$data/plugins/plugins.json")
    test "$before" = "$after" || { echo "managed rewrite on no-op run" >&2; exit 1; }

    # mutable seeds once, then never touches the set again.
    fresh=$(mktemp -d)
    agent2api-sync-plugins mutable "$fresh/plugins" ${manifest.file}
    test -f "$fresh/plugins/plugins.json" || { echo "mutable did not seed" >&2; exit 1; }
    printf '{"packs":[]}' > "$fresh/plugins/plugins.json"
    agent2api-sync-plugins mutable "$fresh/plugins" ${manifest.file}
    jq -e '.packs | length == 0' "$fresh/plugins/plugins.json" >/dev/null || {
      echo "mutable modified an initialized directory" >&2; exit 1;
    }

    touch $out
  '';
}
