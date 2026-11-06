# Handoff — Droidspaces extra modules

## 目标

给 realme RMX5062（mt6989 / android14-6.1 / 内核 6.1.157）补两个 Droidspaces
检查里缺失、但**可以用外部 .ko 补**的功能：

| 模块 | 补齐的检查项 | 说明 |
|---|---|---|
| `ip6table_nat.ko` | `IPv6 NAT` | legacy ip6tables 的 `nat` 表 + MASQUERADE |
| `macvlan.ko` | `Macvlan` | `ip link ... type macvlan` / `--net=macvlan` |

`CFS_BANDWIDTH`、`CGROUP_PIDS` 属于调度器/cgroup 核心，不能运行时补；
`USER_NS`、`devtmpfs` 虽在 Shikochin/Droidspaces-LKM 里有实现，但只适配
PLZ110（qcom,canoe / 6.12.69），不能直接用于本机。

## 仓库

- GitHub: https://github.com/SQL0106/droidspaces-extra-modules
- 分支: `main`
- 关键提交:
  - `cae9bea` Add android14-6.1 macvlan and legacy ip6table_nat modules with CI
  - `f422ea4` Pass GH token to cache verification step
  - `e9aea63` Keep a stable local tag when restoring the DDK image cache

## 模块源码

- `modules/macvlan/macvlan.c`
  - AOSP `kernel/common` `android14-6.1`
  - commit `498f91c17b0822a09aede17d26a63bf8c6813725`
  - `drivers/net/macvlan.c`，原样复制，GPL-2.0-or-later
- `modules/ip6table_nat/ip6table_nat.c`
  - 同 commit，`net/ipv6/netfilter/ip6table_nat.c`，原样复制，GPL-2.0-only
- 依赖符号已在内核中导出：
  - `nf_nat_ipv6_register_fn` / `nf_nat_ipv6_unregister_fn`（GPL）
  - `xt_register_template` / `xt_unregister_template`（GPL）
  - `ip6t_alloc_initial_table`、`ip6t_register_table`、`ip6t_unregister_table_exit`、`ip6t_do_table`

## 构建

- DDK: `ghcr.io/ylarod/ddk-min@sha256:1dd6ac340b627a90a4031d6d0df6b129d8cc949b139fb56032c898f023d3d5d3`
- tag: `android14-6.1-20260313`
- KMI: `android14-6.1`
- CI runner: `ubuntu-latest`（DDK 镜像是 amd64-only；x86 原生跑，避免 QEMU）
- 工作流: `.github/workflows/build.yml`，workflow 名 `build-extra-modules`
- 产物: `out/macvlan.ko`、`out/ip6table_nat.ko`、`out/SHA256SUMS`、`metadata.json`
- artifact 名: `droidspaces-extra-ko-<run_id>`，保留 30 天
- 失败也会执行 `Collect reports`、`Upload ...`、两个 cache save；日志在 artifact 的 `logs/`

## 设备加载

把 `out/*.ko` 推到手机，例如 `/data/local/tmp/`：

```sh
ksud insmod /data/local/tmp/ip6table_nat.ko
ksud insmod /data/local/tmp/macvlan.ko
```

验证：

```sh
ip6tables -t nat -L -n
ip link add link wlan0 name mvtest type macvlan mode bridge && ip link del mvtest
droidspaces check
```

卸载：

```sh
ksud rmmod macvlan
ksud rmmod ip6table_nat
```

## 已知限制

- `macvlan` 在 WiFi STA 模式下通常收不到包（AP 只把帧发给 STA 的 MAC）。
  检查能变 ✓，但容器实际走 macvlan 可能不通；更适合有线/特殊网络。
- `ip6table_nat` 补的是 **legacy ip6tables** 的 nat 表，不是 nftables；
  本机 `ip6tables` 是 legacy，Droidspaces 也走 legacy，所以匹配。
- 模块按 android14-6.1 KMI 编译；KernelSU insmod 绕过 vermagic，
  但仍要求 `Module.symvers` 的符号 CRC 匹配。设备 6.1.157 与 DDK 6.1.x
  同 KMI，现有 `droidspaces_ns` 已证明可行。
- 若模块加载后 `droidspaces check` 仍显示 ✗，先看 `dmesg | tail`，
  再确认 `ksud insmod` 的返回值与 `/proc/modules`。

## 当前状态

- CI run `42256158110`（提交 `f422ea4`）：成功，产出
  `macvlan.ko`（771904 B，sha256 `d56d13e9...`）与
  `ip6table_nat.ko`（522704 B，sha256 `3df37052...`）。
- CI run `42256551318`（提交 `e9aea63`）：成功，DDK 镜像缓存命中，
  `Save DDK image cache` 按预期跳过，`Verify build cache saved` 通过。
- 设备实测：两个模块 `ksud insmod` 均成功；`ip6tables -t nat` 正常；
  macvlan 接口可创建/删除；`droidspaces check` 中 `Macvlan` 与 `IPv6 NAT`
  已变为 ✓。
- KSU 模块已放到 `/data/adb/modules/droidspaces_extra`，`service.sh` 手动执行
  时正确识别“already loaded”；**重启后的自动加载尚未验证**。
- Docker：曾尝试把 `/etc/docker/daemon.json` 改成 `ip6tables: true`，
  Docker 26 要求同时开 `experimental: true`，否则启动失败；已恢复原配置
  （`iptables: false`、`ip6tables: false`），Docker 服务已恢复 active。
