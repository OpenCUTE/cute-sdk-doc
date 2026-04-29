# CUTEFPEVersion Schema 说明

## 概述

`configs/schemas/cute_fpe_version.schema.json` 描述 CUTE/FPE 内部支持的计算格式版本。`ChipyardConfig` 通过：

```yaml
cute:
  fpe:
    version: cute_fpe_v1
```

引用 `configs/cute_fpe_versions/cute_fpe_v1.yaml`。Resolved 阶段再由这些内部计算格式派生软件可见 `capability.datatypes`，避免每个 ChipyardConfig 重复维护长 datatype 列表。

## 示例

```yaml
version: 1
id: cute_fpe_v1
description: Datatype set exported by current ElementDataType/HeaderGenerator.

source:
  generated_header: cutetest/include/datatype.h.generated
  scala_object: cute.ElementDataType

datatypes: [i8i8i32, fp16fp16fp32, bf16bf16fp32, tf32tf32fp32,
            i8u8i32, u8i8i32, u8u8i32,
            mxfp8e4m3fp32, mxfp8e5m2fp32, nvfp4fp32, mxfp4fp32,
            fp8e4m3fp32, fp8e5m2fp32]
```

## 解析规则

`cute-check-config.py` 后续应在 resolved HWConfig 中展开：

```text
ChipyardConfig.cute.fpe.version
  -> configs/cute_fpe_versions/<version>.yaml
  -> resolved capability.datatypes
```
