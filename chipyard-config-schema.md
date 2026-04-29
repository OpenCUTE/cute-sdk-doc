# ChipyardConfig Schema 说明

## 概述

`configs/schemas/chipyard_config.schema.json` 描述现有 Chipyard Scala Config class 的结构化 contract。Phase 0 只支持：

```yaml
mode: existing_class
```

也就是说，本阶段不生成 Scala，只记录并校验 `CuteConfig.scala` 中已有 class 的关键语义。

## 示例

```yaml
version: 1
id: cute2tops_scp64
class: chipyard.CUTE2TopsSCP64Config
source_file: chipyard/generators/chipyard/src/main/scala/config/CuteConfig.scala
mode: existing_class

cute:
  params_symbol: CuteParams.CUTE_2Tops_64SCP
  instances: [0]
  fpe:
    version: cute_fpe_v1
  isa:
    version: cute_isa_v1
  generated_headers:
    output_dir: build/chipyard_configs/cute2tops_scp64/generated_headers
    mode: generate_from_chipyard_config
    fingerprint: auto

soc:
  core:
    kind: shuttle
    count: 1
    shuttle_tile_beat_bytes: 64
  bus:
    system_bits: 512
    memory_bits: 512

capability:
  tensor_ops: [matmul]
  layer_ops: []
  fused_ops: []
```

## 字段归属

| 字段                  | 说明 |
|-----------------------|------|
| class, source_file    | 指向现有 Scala Config class |
| cute.params_symbol    | `WithCuteCoustomParams(...)` 中的 CuteParams 符号 |
| cute.instances        | `WithCUTE(Seq(...))` 中的 core id 列表 |
| cute.fpe              | CUTE/FPE 内部计算格式版本，引用 `configs/cute_fpe_versions/<version>.yaml` |
| cute.isa              | CUTE/YGJK 内部指令集版本，引用 `configs/cute_isa_versions/<version>.yaml` |
| soc.core              | core 类型和数量 |
| soc.bus               | `WithSystemBusWidth` / `WithNBitMemoryBus` |
| soc.cache             | cache/hash/bank/TL monitor 相关配置 |
| capability.tensor_ops | 软件可见 tensor op 能力，供 project target 匹配 |
| trace_capability      | RTL trace 能力占位 |
| cute.generated_headers | 从该 Scala Config 生成 headers 的策略 |

## 后续校验

`cute-check-config.py --chipyard-config <path>` 后续应检查：

```text
1. source_file 存在
2. class 能在 source_file 中找到
3. cute.params_symbol 与 WithCuteCoustomParams 一致
4. cute.instances 与 WithCUTE(Seq(...)) 一致
5. soc.bus 与 WithSystemBusWidth / WithNBitMemoryBus 一致
6. soc.core 与 WithNShuttleCores / WithNSmallBooms / WithNSmallCores 等片段一致
7. soc.cache 与 WithInclusiveCache / WithNBanks / WithCacheHash / WithoutTLMonitors 一致
8. cute.fpe.version 能解析到 `configs/cute_fpe_versions/<version>.yaml`
9. cute.isa.version 能解析到 `configs/cute_isa_versions/<version>.yaml`
10. CUTEISAVersion.groups.cute 的 name/funct/description/return_description 与 `CuteInstConfigs.allInsts` 一致
11. CUTEISAVersion.groups.ygjk 的 name/funct/description/return_description 与 `YGJKInstConfigs.allInsts` 一致
12. `instruction.h.generated` 中 `CUTE_INST_FUNCT_<name>` 宏值与 CUTEISAVersion.rocc_funct 一致
```
