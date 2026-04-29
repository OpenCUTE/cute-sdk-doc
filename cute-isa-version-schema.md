# CUTEISAVersion Schema 说明

## 概述

`configs/schemas/cute_isa_version.schema.json` 描述 CUTE/YGJK 内部支持的指令集版本。`ChipyardConfig` 通过：

```yaml
cute:
  isa:
    version: cute_isa_v1
```

引用 `configs/cute_isa_versions/cute_isa_v1.yaml`。Resolved 阶段再由该对象派生软件可见 `capability.instructions`，避免每个 ChipyardConfig 重复维护指令列表。

## 示例

```yaml
version: 1
id: cute_isa_v1
description: CUTE/YGJK instruction set exported by current CuteInstConfigs, YGJKInstConfigs, and HeaderGenerator.

source:
  scala_file: src/main/scala/CUTEParameters.scala
  scala_objects:
    - cute.CuteInstConfigs
    - cute.YGJKInstConfigs
  generated_header: cutetest/include/instruction.h.generated

rocc:
  opcode: 0x0B
  cute_internal_offset: 64

groups:
  ygjk:
    scala_object: cute.YGJKInstConfigs
    description: YGK/RoCC interface instructions handled directly at the RoCC interface layer.
    rocc_funct_offset: 0
    instructions:
      - name: QUERY_ACCELERATOR_BUSY
        funct: 1
        rocc_funct: 1
        description: 查询加速器是否正在运行
        return_description: 返回加速器是否忙碌 (1=忙碌, 0=空闲)
  cute:
    scala_object: cute.CuteInstConfigs
    description: CUTE internal control instructions forwarded to the CUTE core through RoCC funct offset 64.
    rocc_funct_offset: 64
    instructions:
      - name: SEND_MACRO_INST
        funct: 0
        rocc_funct: 64
        description: 发送已配置的宏指令到指令FIFO
        return_description: 返回指令在FIFO中的编号
```

## 解析规则

`cute-check-config.py` 后续应在 resolved HWConfig 中展开：

```text
ChipyardConfig.cute.isa.version
  -> configs/cute_isa_versions/<version>.yaml
  -> resolved capability.instructions
```

## 对齐检查

后续 check 应确认：

```text
groups.cute.instructions  == CuteInstConfigs.allInsts 的 name/funct/description/returnDescription 集合
groups.ygjk.instructions  == YGJKInstConfigs.allInsts 的 name/funct/description/returnDescription 集合
groups.cute.rocc_funct    == funct + 64
groups.ygjk.rocc_funct    == funct
instruction.h.generated   == CUTE_INST_FUNCT_<name> 宏值与 rocc_funct 一致
```
