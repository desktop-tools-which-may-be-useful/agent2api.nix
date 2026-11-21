# agent2api.nix

[Agent2API](https://github.com/aimod-cc/Agent2API) 的插件打包与 NixOS 模块。

- **插件包**：把上游签名的 release zip 解包，原生 ELF 用 `autoPatchelfHook` 修好，
  使其能在 NixOS 上运行（上游二进制硬编码 `/lib64/ld-linux-x86-64.so.2`，在 NixOS
  上会 `exit code 127`）。wasm 插件原样打包。
- **NixOS 模块**：提供 `services.agent2api`，在服务启动前把声明的插件同步到
  `$stateDir/plugins`，再启动网关。两种模式：
  - `managed`：每次启动对账插件集合与 `plugins.json`（含每个 provider 的
    `enabled` 开关），未声明的插件会被移除。
  - `mutable`：仅当网关从未初始化过（没有 `plugins.json`）时 seed 一次，之后
    完全不动插件目录。

插件目录使用**符号链接**指向 Nix store，未变更时不产生任何拷贝或重写。

## 使用

```nix
{
  inputs.agent2api-nix.url = "github:desktop-tools-which-may-be-useful/agent2api.nix";

  # 在 NixOS 配置中
  imports = [ inputs.agent2api-nix.nixosModules.default ];

  services.agent2api = {
    enable = true;
    package = nur-DataEraserC.packages.${pkgs.system}.agent2api-server;
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

## 维护

`pkgs/plugins.nix` 由上游索引
[`Agent2plugin/Agent2plugin`](https://github.com/Agent2plugin/Agent2plugin) 的
`index.json` 生成，每个条目对应 `Agent2Builder/agent2api-providers-releases` 的一个
release 资产。新增或升级插件时更新该文件的 `version`/`url`/`hash`/`zipSha256`
（`hash` 与 `zipSha256` 都来自同一个 zip）。

`checks` 会验证：

- 所有原生插件的 ELF 解释器已被 patchelf 到 `/nix/store`；
- 同步脚本的目录布局、managed 幂等性、mutable 只 seed 一次。
