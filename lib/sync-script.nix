{ pkgs }:
pkgs.writeShellApplication {
  name = "agent2api-sync-plugins";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.diffutils # cmp, used for the registry no-op check
    pkgs.findutils
    pkgs.jq
  ];

  text = ''
    set -euo pipefail

    mode="''${1:?usage: agent2api-sync-plugins <managed|mutable> <pluginsDir> <manifest>}"
    pluginsDir="''${2:?usage: agent2api-sync-plugins <managed|mutable> <pluginsDir> <manifest>}"
    manifest="''${3:?usage: agent2api-sync-plugins <managed|mutable> <pluginsDir> <manifest>}"

    # mutable: initialize once, then never touch the plugin set again.
    if [ "$mode" = mutable ] && [ -f "$pluginsDir/plugins.json" ]; then
      exit 0
    fi

    mkdir -p "$pluginsDir"

    # 1) Link each declared pack at plugins/<id>/<version> -> store path.
    #    Skip the write when the link already points at the right target, so
    #    an unchanged launch does not touch the filesystem.
    while IFS=$'\t' read -r id version path; do
      [ -n "$id" ] || continue
      target="$pluginsDir/$id/$version"

      # Drop any other version of this id (stale update, runtime install).
      find "$pluginsDir/$id" -mindepth 1 -maxdepth 1 ! -name "$version" \
        -exec rm -rf -- {} + 2>/dev/null || true

      mkdir -p "$pluginsDir/$id"
      if [ "$(readlink -- "$target" 2>/dev/null || true)" != "$path" ]; then
        ln -sfn -- "$path" "$target"
      fi
    done < <(jq -r '.packs[] | [.id, .version, .path] | @tsv' "$manifest")

    # 2) Remove plugin dirs the declaration no longer lists (managed; a
    #    mutable first seed starts from an empty set anyway).
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      name=''${dir##*/}
      if ! jq -e --arg id "$name" 'any(.packs[]; .id == $id)' "$manifest" >/dev/null; then
        rm -rf -- "$dir"
      fi
    done < <(find "$pluginsDir" -mindepth 1 -maxdepth 1 -type d ! -name .staging)

    # 3) Rewrite the registry only when it differs. The provider enabled map
    #    is derived from pack.json, so managed mode also resets UI toggles.
    tmp=$(mktemp "$pluginsDir/.plugins.json.XXXXXX")
    jq '{
      packs: [.packs[] | {
        id, version, enabled: true, providers, entry, sha256,
        signed: false, installed_at: 0, manifest_providers
      }]
    }' "$manifest" > "$tmp"

    if cmp -s -- "$tmp" "$pluginsDir/plugins.json"; then
      rm -f -- "$tmp"
    else
      mv -f -- "$tmp" "$pluginsDir/plugins.json"
    fi
  '';

  meta.description = "Reconcile Agent2API's plugin directory with the Nix-declared set";
}
