# Droidspaces extra modules (android14-6.1)

为 realme RMX5062（mt6989，内核 6.1.157）补两个 Droidspaces 检查缺失的内核模块：

| 模块 | 作用 | Droidspaces 检查项 |
|---|---|---|
| `ip6table_nat.ko` | legacy ip6tables 的 `nat` 表和 MASQUERADE target | `IPv6 NAT` → ✓，Docker 可去掉 `"ip6tables": false` |
| `macvlan.ko` | `ip link ... type macvlan` / `--net=macvlan` | `Macvlan` → ✓ |

依赖均已在内核中启用：`NF_NAT=y`、`NF_NAT_MASQUERADE=y`、`NETFILTER_XT_TARGET_MASQUERADE=y`、`IP6_NF_IPTABLES=y`、`NF_CONNTRACK=y`；只缺 `CONFIG_IP6_NF_NAT` 和 `CONFIG_MACVLAN`。

## 为什么 CI 用 x86 的 `ubuntu-latest`

`ghcr.io/ylarod/ddk-min` 是 **amd64-only** 的 DDK 镜像，里面同时带 android14-6.1 的
`kdir`（含 `Module.symvers`）和 aarch64 交叉 clang。GitHub 的 `ubuntu-latest`
可以原生运行它；若换到 `ubuntu-24.04-arm`，要么用 QEMU 跑 amd64 镜像（更慢），
要么自己重建 DDK 里的 x86 host 工具（`fixdep`/`modpost` 等），反而复杂。
这两个模块各只有一个 C 文件，x86 runner 上编译只需要几十秒。

## CI 设计

- **固定镜像**：`build/targets.json` 记录 DDK tag 和不可变 digest。
- **缓存**：
  - DDK 镜像 tar 按 digest 缓存（超过 6 GB 自动跳过，避免撞 10 GB 上限）；
  - `.build/` 和 `out/` 按源码哈希 + run id 缓存，失败也会保存。
- **失败保留**：`Build` 失败后仍执行 `Collect reports`、`Upload modules, logs and metadata`
  和两个 cache save；artifact 里包含 `out/*.ko`（如果有）、`logs/*.log`、
  `logs/*.status`、`metadata.json`、`logs/ddk-env.log`、`logs/files.txt`。
- **并发**：`cancel-in-progress: false`，不取消旧 run，避免丢掉失败日志。
- **验证**：成功时通过 `actions/caches` API 自检 build cache 是否真的保存；
  失败时不额外报红，避免掩盖构建错误。

## 构建步骤

GitHub Actions 里手动运行 `build-extra-modules`，可选 `all` / `macvlan` / `ip6table_nat`。
本地（有 Docker 的 amd64 机器）：

```sh
bash scripts/build.sh
```

产物：

```
out/macvlan.ko
out/ip6table_nat.ko
out/SHA256SUMS
metadata.json
logs/
```

## 设备上加载

把 `out/*.ko` 推到手机（例如 `/data/local/tmp/`），以 root 加载：

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

## 开机自动加载（KernelSU）

`out/droidspaces_extra-ksu.zip` 是 KernelSU 模块包，包含两个 `.ko` 和 `service.sh`。
在 KernelSU 管理器中安装后重启即可；也可命令行安装：

```sh
ksud module install /data/local/tmp/droidspaces_extra-ksu.zip
```

`service.sh` 在 late_start 阶段用 `ksud insmod` 加载；如果 `/proc/modules`
里已经有同名模块就跳过，避免重复加载报错。

## 实测结果（realme RMX5062，2026-11-07）

- `/data/adb/ksud insmod` 加载两个模块均 `rc=0`，`/proc/modules` 可见。
- `ip6tables -t nat -L -n` 正常列出四条链。
- `ip link add link wlan0 name mvtest0 type macvlan mode bridge` 和 `ip link del` 均 `rc=0`。
- `droidspaces check`：`Macvlan support` ✓、`IPv6 NAT support` ✓；
  仍为 ✗ 的是 `devtmpfs`、`CPU limit`、`Process limit`、`user namespaces`。
- 已安装 KSU 模块 `/data/adb/modules/droidspaces_extra`；重启后的自动加载尚未验证
  （没有擅自重启设备）。

## 注意

- `macvlan` 在 WiFi STA 模式（`wlan0` 连 AP）下通常收不到包，因为 AP 只把帧转发给
  STA 的 MAC。check 能变 ✓，但容器真正走 macvlan 可能不通；更适合有线/特殊网络。
- `ip6table_nat` 是 **legacy ip6tables** 的 nat 表，不是 nftables。Droidspaces 的检查
  和本机 `ip6tables` 都走 legacy，所以对得上。
- 模块按 GKI android14-6.1 KMI 编译。KernelSU 的 insmod 会绕过 vermagic；
  仍要求 `Module.symvers` 的符号 CRC 匹配。设备当前 6.1.157 与 DDK 的 6.1.x
  基线同属 android14-6.1 KMI，现有 `droidspaces_ns` 已证明这条路可行。
- `macvlan.ko` 编译时定义了 `CONFIG_MACVLAN_MODULE=1`，只影响头文件里的
  `IS_ENABLED(CONFIG_MACVLAN)` 内联函数，不改变结构体布局。

## 源码来源

- `modules/macvlan/macvlan.c`：AOSP `kernel/common` `android14-6.1`
  (`498f91c17b0822a09aede17d26a63bf8c6813725`)，`drivers/net/macvlan.c`
- `modules/ip6table_nat/ip6table_nat.c`：同一 commit，`net/ipv6/netfilter/ip6table_nat.c`
- 两者均为 GPL-2.0，文件头保留 SPDX 与原始版权。
