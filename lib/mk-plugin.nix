# Build one Agent2API provider-plugin pack from its signed release zip.
#
# The gateway runs plugins as child processes: each pack is a `pack.json`
# plus an `entry` binary (native ELF or wasm) speaking newline-delimited
# JSON-RPC. Upstream's native builds link against a distro glibc
# (`/lib64/ld-linux-x86-64.so.2`), which does not exist on NixOS; the
# gateway then reports `exit code 127` / stdout EOF. autoPatchelfHook
# rewrites the interpreter and RPATH so the pack runs on NixOS. wasm packs
# (`native = false`) are copied unchanged.
#
# The output is the unpacked pack tree. The activation sync step links
# `plugins/<id>/<version>` at this store path, so the gateway executes the
# patched binary directly from the store (no per-start copying).
{ pkgs }:
{
  id,
  version,
  native,
  url,
  hash,
  # Hex sha256 of the release zip, recorded in the gateway's plugins.json.
  zipSha256 ? "",
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = id;
  inherit version;

  src = pkgs.fetchurl { inherit url hash; };

  nativeBuildInputs = [ pkgs.unzip ] ++ pkgs.lib.optionals native [ pkgs.autoPatchelfHook ];
  buildInputs = pkgs.lib.optionals native [ pkgs.stdenv.cc.cc.lib ];

  unpackPhase = "unzip -q $src";

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a ./. $out/
    runHook postInstall
  '';

  passthru = {
    inherit zipSha256;
    target = if native then "x86_64-unknown-linux-gnu" else "wasm32-unknown-unknown";
  };

  meta = {
    description = "Agent2API provider plugin ${id}";
    license = pkgs.lib.licenses.agpl3Only;
    platforms = pkgs.lib.platforms.linux;
  };
}
