# HWConfig Schema 说明

## 概述

`configs/schemas/hwconfig.schema.json` 定义 CUTE 框架中的**可运行硬件目标组合**。每份 `configs/hwconfigs/*.yaml` 文件必须符合这个 schema。

HWConfig 不再直接描述 core、bus、cache、capability 或 generated headers。这些属于 `ChipyardConfig`。HWConfig 只组合：

```text
ChipyardConfig + memory model + simulator policy
```

## 顶层结构

```text
version          — schema 版本，当前固定为 1
name             — 唯一标识，如 cute2tops_scp64_dramsim32
tags             — 供 project 做 target 匹配
chipyard_config  — 引用 configs/chipyard_configs/<id>.yaml
memory           — memory model 配置引用
simulator        — 仿真器策略
```

其中 `version`、`name`、`chipyard_config`、`memory`、`simulator` 为必填。

## 示例

```yaml
version: 1
name: cute2tops_scp64_dramsim32
tags: [cute_tensor_v1, shuttle, small]

chipyard_config: cute2tops_scp64

memory:
  model: dramsim2
  config: dramsim2_ini_32GB_per_s

simulator:
  backend: verilator
  binary: auto
  max_cycles: 800000000
```

## 字段说明

### chipyard_config

引用 `configs/chipyard_configs/<id>.yaml`。例如：

```yaml
chipyard_config: cute2tops_scp64
```

工具应解析到：

```text
configs/chipyard_configs/cute2tops_scp64.yaml
```

### memory

当前不引入独立 `memconfig.yaml`，`model/config` 直接指向 `configs/memconfigs/<model>/<config>/`。

| 字段   | 类型   | 说明                                           |
|--------|--------|------------------------------------------------|
| model  | string | 内存模型类型：`dramsim2` / `none`              |
| config | string | 配置目录名，如 `dramsim2_ini_32GB_per_s`。当 `model=dramsim2` 时必填 |

### simulator

| 字段       | 类型    | 说明                                   |
|------------|---------|----------------------------------------|
| backend    | string  | 仿真后端：`verilator` / `vcs` / `fpga` |
| binary     | string  | `auto` 或指定仿真器路径                |
| max_cycles | integer | 最大仿真周期数                         |

## 解析规则

`cute-check-config.py` 后续应将 HWConfig 解析成 resolved HWConfig：

```text
tags                     来自 HWConfig
memory / simulator       来自 HWConfig
soc / op capability      来自 ChipyardConfig
datatype capability      由 ChipyardConfig.cute.fpe.version 引用的 CUTEFPEVersion 派生
instruction capability   由 ChipyardConfig.cute.isa.version 引用的 CUTEISAVersion 派生
trace_capability         来自 ChipyardConfig
generated_headers        来自 ChipyardConfig
```

这样同一个 `ChipyardConfig` 可以被多个 memory/simulator 组合复用，例如 32GB/48GB DRAMSim2。

## 人工维护 vs 自动生成

| 字段                    | 归属 |
|-------------------------|------|
| name, tags              | HWConfig 人工维护 |
| chipyard_config         | HWConfig 人工维护引用 |
| memory.*, simulator.*   | HWConfig 人工维护 |
| soc.*, tensor/layer/fused capability | 来自 ChipyardConfig |
| datatype capability     | 来自 CUTEFPEVersion |
| instruction capability  | 来自 CUTEISAVersion |
| generated_headers.*     | 来自 ChipyardConfig，工具自动执行 |
