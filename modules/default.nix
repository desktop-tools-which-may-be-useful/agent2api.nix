{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.agent2api;

  inherit (cfg) stateDir;

  useStateDirectory = builtins.dirOf stateDir == "/var/lib";

  pluginManifest = import ../lib/make-manifest.nix { inherit pkgs; } {
    plugins = cfg.plugins;
  };

  syncScript = import ../lib/sync-script.nix { inherit pkgs; };

  # A wrapper runs the plugin sync, then execs the real server. The systemd
  # unit's ExecStart points at the wrapper selected by `mode`, so the plugin
  # set is reconciled before the gateway reads it on startup.
  wrapperFor =
    mode:
    pkgs.writeShellApplication {
      name = "agent2api-${mode}";
      runtimeInputs = [ syncScript ];
      text = ''
        agent2api-sync-plugins ${mode} "''${AGENT2API_PROXY_HOME:?AGENT2API_PROXY_HOME is not set}" ${pluginManifest.file}
        exec ${lib.getExe cfg.package} "$@"
      '';
    };

  adminPasswordCredential = "admin-password";

  startScript =
    mode:
    pkgs.writeShellScript "agent2api-${mode}-start" ''
      if [ -n "''${CREDENTIALS_DIRECTORY-}" ] && [ -r "$CREDENTIALS_DIRECTORY/${adminPasswordCredential}" ]; then
        AGENT2API_ADMIN_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/${adminPasswordCredential}")"
        export AGENT2API_ADMIN_PASSWORD
      fi
      exec ${wrapperFor mode} "$@"
    '';
in
{
  options.services.agent2api = {
    enable = lib.mkEnableOption "Agent2API multi-provider gateway";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        Agent2API headless server package (the `agent2api-server` binary). The
        plugin packages come from `services.agent2api.plugins`.
      '';
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "managed"
        "mutable"
      ];
      default = "managed";
      description = ''
        Which systemd unit is started:

        - `managed`: reconcile `plugins/` and `plugins.json` with `plugins` on
          every start. Plugin set and per-provider enabled flags are reset to
          the declaration.
        - `mutable`: seed the declared set only if the gateway has never been
          initialized (no `plugins.json`); afterwards never touch the plugin
          directory again.
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression ''
        [ agent2api-nix.packages.${pkgs.system}.agent2api-web-providers ]
      '';
      description = ''
        Provider-plugin packs to install. Empty by default: the gateway starts
        with no extra providers and the user adds them here.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the gateway binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3065;
      description = "Port of the OpenAI-compatible gateway (`/v1/*`).";
    };

    panelPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Serve the management panel on its own port; must differ from `port`.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/agent2api";
      description = "Writable directory holding the database and `plugins/`.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "agent2api";
      description = "User account under which the service runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "agent2api";
      description = "Group under which the service runs.";
    };

    adminUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Pre-provision the panel administrator; requires `adminPasswordFile`.";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "File with the panel administrator password, loaded as a systemd credential.";
    };

    allowNoKey = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve `/v1/*` without an API key (trusted, isolated hosts only).";
    };

    captcha = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Offer the login page's human-verification widget.";
    };

    verbose = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Log at debug level.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the gateway (and panel) ports in the firewall.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Environment file as defined in systemd.exec(5).";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for the service.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (p: builtins.pathExists "${p}/pack.json") cfg.plugins;
        message = ''
          services.agent2api.plugins contains an entry without `pack.json`.
          Use the plugin packages from the agent2api-nix flake (they expose the
          unpacked pack tree), not the upstream release zip.
        '';
      }
      {
        assertion = cfg.user == "agent2api" || builtins.hasAttr cfg.user config.users.users;
        message = ''services.agent2api.user is set to "${cfg.user}", which is not defined.'';
      }
      {
        assertion = cfg.group == "agent2api" || builtins.hasAttr cfg.group config.users.groups;
        message = ''services.agent2api.group is set to "${cfg.group}", which is not defined.'';
      }
      {
        assertion = cfg.adminPasswordFile == null || cfg.adminUser != null;
        message = "services.agent2api.adminPasswordFile requires adminUser.";
      }
      {
        assertion = cfg.panelPort == null || cfg.panelPort != cfg.port;
        message = "services.agent2api.panelPort must differ from port.";
      }
    ];

    users.users = lib.mkIf (cfg.user == "agent2api") {
      agent2api = {
        isSystemUser = true;
        inherit (cfg) group;
        home = stateDir;
        description = "Agent2API service user";
      };
    };

    users.groups = lib.mkIf (cfg.group == "agent2api") {
      agent2api = { };
    };

    systemd.services = lib.genAttrs [ "agent2api-managed" "agent2api-mutable" ] (
      name:
      let
        mode = lib.removePrefix "agent2api-" name;
        active = cfg.mode == mode;
      in
      {
        description = "Agent2API multi-provider gateway (${mode} plugins)";
        documentation = [ "https://github.com/aimod-cc/Agent2API" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = lib.optional active "multi-user.target";
        # Keep the familiar `agent2api.service` name pointing at the active unit.
        aliases = lib.optional active "agent2api.service";

        environment = {
          AGENT2API_PROXY_HOME = stateDir;
          AGENT2API_HOST = cfg.host;
          AGENT2API_PROXY_PORT = toString cfg.port;
          AGENT2API_CAPTCHA_ENABLED = if cfg.captcha then "1" else "0";
          AGENT2API_SELF_UPDATE = "0";
        }
        // lib.optionalAttrs (cfg.panelPort != null) {
          AGENT2API_PANEL_PORT = toString cfg.panelPort;
        }
        // lib.optionalAttrs (cfg.adminUser != null) {
          AGENT2API_ADMIN_USER = cfg.adminUser;
        }
        // lib.optionalAttrs cfg.allowNoKey {
          AGENT2API_ALLOW_NO_KEY = "1";
        }
        // lib.optionalAttrs cfg.verbose {
          AGENT2API_VERBOSE = "1";
        }
        // cfg.extraEnvironment;

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = startScript mode;
          Restart = "on-failure";
          RestartSec = 5;
          LoadCredential = lib.optionals (cfg.adminPasswordFile != null) [
            "${adminPasswordCredential}:${cfg.adminPasswordFile}"
          ];
          EnvironmentFile = lib.mkIf (cfg.environmentFile != null) [ cfg.environmentFile ];

          CapabilityBoundingSet = "";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectHostname = true;
          ProtectClock = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
          RestrictNamespaces = true;
          RestrictSUIDSGID = true;
          RestrictRealtime = true;
          RemoveIPC = true;
          LockPersonality = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
            "~@resources"
          ];
          UMask = "0077";
        }
        // lib.optionalAttrs useStateDirectory {
          StateDirectory = [ (builtins.baseNameOf stateDir) ];
          StateDirectoryMode = "0700";
        }
        // lib.optionalAttrs (!useStateDirectory) {
          ReadWritePaths = [ stateDir ];
        };
      }
    );

    system.activationScripts.agent2api = lib.stringAfter [ "users" ] ''
      install -d -m 0700 ${lib.escapeShellArg stateDir}
      chown ${cfg.user}:${cfg.group} ${lib.escapeShellArg stateDir}
    '';

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ] ++ lib.optional (cfg.panelPort != null) cfg.panelPort;
    };
  };
}
