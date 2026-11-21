# Build a standalone launcher: `agent2api_<mode>` that syncs the declared
# plugins into a writable data directory and then execs the server. No
# systemd, no NixOS: run it with `nix run` or install it into a profile.
#
# The data directory defaults to $AGENT2API_PROXY_HOME, then
# $XDG_DATA_HOME/agent2api, then ~/.local/share/agent2api. The sync script
# links plugins from the store, so only the small registry is written.
{ pkgs }:
{
  package,
  plugins,
  mode,
  dataDir ? null,
  # Where the gateway expects its plugin registry. Defaults to
  # $AGENT2API_PROXY_HOME/plugins; set it to place the directory elsewhere.
  pluginsDir ? null,
}:
let
  lib = pkgs.lib;
  manifest = import ./make-manifest.nix { inherit pkgs; } { inherit plugins; };
  sync = import ./sync-script.nix { inherit pkgs; };
  dataDirExpr =
    if dataDir == null then
      ''"''${AGENT2API_PROXY_HOME:-''${XDG_DATA_HOME:-$HOME/.local/share}/agent2api}"''
    else
      lib.escapeShellArg dataDir;
  pluginsDirExpr =
    if pluginsDir == null then ''"''${AGENT2API_PROXY_HOME}/plugins"'' else lib.escapeShellArg pluginsDir;
in
pkgs.writeShellApplication {
  name = "agent2api_${mode}";

  runtimeInputs = [
    sync
    pkgs.coreutils
  ];

  text = ''
    export AGENT2API_PROXY_HOME=${dataDirExpr}
    mkdir -p "$AGENT2API_PROXY_HOME"
    agent2api-sync-plugins ${mode} ${pluginsDirExpr} ${manifest.file}
    exec ${lib.getExe package} "$@"
  '';

  meta = {
    description = "Agent2API gateway with ${mode} plugin sync (standalone launcher)";
    mainProgram = "agent2api_${mode}";
    platforms = lib.platforms.linux;
  };
}
