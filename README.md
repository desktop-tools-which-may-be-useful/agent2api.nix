# agent2api.nix

[Agent2API](https://github.com/aimod-cc/Agent2API) 的打包（server / desktop / 全部 provider
插件）与 NixOS 模块。

- **插件包**：把上游签名的 release zip 解包，原生 ELF 用 `autoPatchelfHook` 修好，
  使其能在 NixOS 上运行（上游二进制硬编码 `/lib64/ld-linux-x86-64.so.2`，在 NixOS
  上会 `exit code 127`）。wasm 插件原样打包。
- **server / desktop**：`agent2api-server`（headless）与 `agent2api-desktop`（Tauri
  面板），从本仓库维护，不再放在 nur。
- **NixOS 模块**：`services.agent2api`，在服务启动前把声明的插件同步到
  `pluginsDir`，再启动网关。两种模式：
  - `managed`：每次启动对账插件集合与 `plugins.json`（含每个 provider 的
    `enabled` 开关），未声明的插件会被移除。
  - `mutable`：仅当网关从未初始化过（没有 `plugins.json`）时 seed 一次，之后
    完全不动插件目录。
- **独立运行包**：`agent2api_managed` / `agent2api_mutable` 是纯 `writeShellApplication`，
  不依赖 systemd/NixOS，`nix run` 即可。

插件目录使用**符号链接**指向 Nix store，未变更时不产生任何拷贝或重写。

## 包

```nix
inputs.agent2api-nix.packages.${system}
# agent2api-server, agent2api-desktop
# agent2api-providers, agent2api-web-providers
# agent2api-wasm-trae, agent2api-wasm-zcode, ...（共 41 个插件）
# agent2api_managed, agent2api_mutable（独立运行包）
```

独立运行：

```sh
# 数据目录默认 $AGENT2API_PROXY_HOME，其次 $XDG_DATA_HOME/agent2api
nix run github:desktop-tools-which-may-be-useful/agent2api.nix#agent2api_managed

# 端口/管理员等仍走 Agent2API 自己的环境变量
AGENT2API_PROXY_PORT=1108 AGENT2API_HOST=127.0.0.1 \
  nix run .#agent2api_mutable
```

`agent2api_managed` 默认带上全部 41 个插件；需要自定义集合时用
`lib.mk-standalone.nix`（见 `flake.nix` 里的 `standalone` 调用）。

## NixOS

```nix
{
  inputs.agent2api-nix.url = "github:desktop-tools-which-may-be-useful/agent2api.nix";

  imports = [ inputs.agent2api-nix.nixosModules.default ];

  services.agent2api = {
    enable = true;
    package = inputs.agent2api-nix.packages.${pkgs.system}.agent2api-server;
    mode = "managed";            # 或 "mutable"
    plugins = with inputs.agent2api-nix.packages.${pkgs.system}; [
      agent2api-web-providers    # 网页提供商（原生）
      agent2api-providers        # 提供商增强（原生）
      agent2api-wasm-trae        # Trae（wasm）
      agent2api-wasm-zcode       # ZCode 国内版（wasm）
    ];
  };
}
```

`plugins` 默认为空：不带任何插件启动，由使用者按需声明。

常用选项：`stateDir`（默认 `/var/lib/agent2api`）、`pluginsDir`（默认
`stateDir/plugins`，可指向任意目录，模块会创建并授权）、`user`/`group`、
`host`/`port`/`panelPort`、`adminUser`/`adminPasswordFile`、`allowNoKey`、
`captcha`、`extraEnvironment`。

## 维护

`pkgs/plugins.nix` 由上游索引
[`Agent2plugin/Agent2plugin`](https://github.com/Agent2plugin/Agent2plugin) 的
`index.json` 生成，每个条目对应 `Agent2Builder/agent2api-providers-releases` 的一个
release 资产。新增或升级插件时更新该文件的 `version`/`url`/`hash`/`zipSha256`
（`hash` 与 `zipSha256` 都来自同一个 zip）。

`checks` 会验证：

- 所有原生插件的 ELF 解释器已被 patchelf 到 `/nix/store`；
- 同步脚本的目录布局、managed 幂等性、mutable 只 seed 一次。
