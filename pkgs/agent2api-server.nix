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
  rust-jemalloc-sys,
  sqlite,
  zstd,
  pkg-config,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "agent2api-server";
  version = "3.5.1";

  src = fetchFromGitHub {
    owner = "aimod-cc";
    repo = "Agent2API";
    tag = "v${finalAttrs.version}";
    hash = "sha256-lud9KIhntrCW652jGK5D3sJdxLg92VROHkxYUe1hT6U=";
  };

  cargoRoot = "desktop-tauri/src-tauri";
  buildAndTestSubdir = "desktop-tauri/src-tauri";

  cargoHash = "sha256-6tiEMf8ukFXNEtt6lpLWCiqD7/VXgy7yL8CewwYUbBs=";

  cargoBuildFlags = [
    "-p"
    "agent2api-server"
  ];
  cargoTestFlags = [
    "-p"
    "agent2api-server"
  ];

  # v3.4.1 needed ./agent2api-server-test-drift.patch to repair stale test
  # call sites; upstream v3.5.1 fixed them, so no patches are carried now.

  # nixpkgs' cargo-setup-hook forces the system-library probes for the
  # transitive tikv-jemalloc-sys (JEMALLOC_OVERRIDE points at a deliberately
  # nonexistent sentinel), libsqlite3-sys (LIBSQLITE3_SYS_USE_PKG_CONFIG=1)
  # and, since v3.5.1, zstd-sys (ZSTD_SYS_USE_PKG_CONFIG=1); hand them system
  # libraries instead of letting the build panic.
  buildInputs = [
    rust-jemalloc-sys
    sqlite
    zstd
  ];
  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

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
