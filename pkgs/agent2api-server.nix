# Agent2API headless server, packaged so the standalone `agent2api_managed` /
# `agent2api_mutable` packages and the NixOS module share one binary.
#
# Upstream LICENSE is MIT plus a usage notice that forbids commercial use and
# paid redistribution, so it is marked unfree (the flake enables allowUnfree).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  nix-update-script,
  makeWrapper,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "agent2api-server";
  version = "3.4.2";

  src = fetchFromGitHub {
    owner = "aimod-cc";
    repo = "Agent2API";
    tag = "v${finalAttrs.version}";
    hash = "sha256-B2YjdzU/cbgli5WFEy4naDJIwipcAg6vsACcaagiBD0=";
  };

  cargoRoot = "desktop-tauri/src-tauri";
  buildAndTestSubdir = "desktop-tauri/src-tauri";

  cargoHash = "sha256-nMIYEUCJJ5ZMyKRDw1YreTIX4Rfi5ysg0cIC6JzAWzA=";

  cargoBuildFlags = [
    "-p"
    "agent2api-server"
  ];
  cargoTestFlags = [
    "-p"
    "agent2api-server"
  ];

  # Upstream v3.4.1 test code predates its own type changes (RequestQuery,
  # WebDavConfig, send_with_retry); the library and binary compile, only the
  # test targets fail. Repair the call sites and ignore the obsolete CodeArts
  # classifier case, which moved to the out-of-tree providers plugin.
  patches = [ ./agent2api-server-test-drift.patch ];

  nativeBuildInputs = [ makeWrapper ];

  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  postInstall = ''
    mkdir -p $out/share/agent2api
    cp -r ${finalAttrs.src}/desktop-tauri/ui $out/share/agent2api/ui

    mkdir -p $out/libexec
    mv $out/bin/agent2api-server $out/libexec/agent2api-server

    makeWrapper $out/libexec/agent2api-server $out/bin/agent2api-server \
      --set-default AGENT2API_UI_DIR $out/share/agent2api/ui
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    changelog = "https://github.com/aimod-cc/Agent2API/releases/tag/v${finalAttrs.version}";
    description = "Headless gateway that exposes multi-provider AI client logins as OpenAI-compatible APIs";
    homepage = "https://github.com/aimod-cc/Agent2API";
    license = lib.licenses.unfree;
    mainProgram = "agent2api-server";
    platforms = lib.platforms.linux;
  };
})
