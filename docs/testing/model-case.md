# 添加模型阶段与 checkpoint

新阶段需要三部分：SDK 数值核、独立 reference、任务输出描述。当前迁移的
生成器是 `tests/models/generate.py`，双平台共同入口为 `tests/models/model.c`。
生成数据写在仓库外，源码树只维护生成规则。

## 输入和输出

输入使用确定种子的非零数组，打包为 ELF 的只读数据；输出放入对齐的 `.data`
符号，避免裸机启动清零大 BSS 的模拟开销。初始 sentinel 不是计算结果：检查器
仍要求每一个输出字节在任务完成前得到新的写 ack。

输入、bias、token scale、权重 scale 和数据布局都属于数值契约。矩阵 B 的
逻辑形状是 N×K；当前迁移 GEMM 使用 64×64 tile，M/N/K 是 64 的整数倍。
BERT 多 head 的输出 stride 是完整 hidden width，不能误写为单 head width。
所有共享数组起始地址按 64 字节对齐。声明一项较大 buffer 并不授权越界写入。

## 任务描述示例

```json
{
  "hart": 0,
  "seq": 2,
  "key": 2,
  "name": "context_quant",
  "outputs": [
    {"symbol": "context_scale", "bytes": 256, "oracle": "context_scale.oracle.bin"},
    {"symbol": "context_q8", "bytes": 8192, "oracle": "context_q8.oracle.bin"}
  ]
}
```

这是单任务片段。runner 根据两个 ELF 分别解析同名符号，要求 `bytes` 与符号
长度一致、地址对齐。QEMU marker 到达时导出全部区域；RTL marker 到达时
检查全部区域。`seq` 表示本 hart 的完成次序，`key` 用于识别阶段，不能与
TileLink source 或 catalog 的 task ID 混为一谈。

一次任务可包含多条 CUTE 宏指令和 RVV 指令，但标记前必须等待其全部输出
完成。CUTE 任务按 FIFO 顺序 wait/clear；最后调用 `cute_checkpoint`。当前
checkpoint 会排空该 hart。需要重用同一地址时，为后续任务再声明新的输出版本。

## Reference 的两种方式

普通 `oracle` 是固定输入对应的独立 NumPy 输出，默认逐字节校准 QEMU。
浮点数学 reference 可以使用下面的显式描述：

```json
"oracle_compare": {
  "mode": "float_tolerance",
  "dtype": "<f4",
  "rtol": 0.00003,
  "atol": 0.000003
}
```

这个设置不影响 RTL/QEMU 比较。整数结果没有容差。NaN、Inf、长度不符或
非法 dtype 不会因为容差配置而通过。

如果上游包含允许近似的计算，可以用 `oracle_expression` 指定独立运算，输入
引用已校准任务的 `(hart, task_seq, symbol, dtype, shape)`，或当前 fixture
目录中带哈希的输入文件。引用本任务/未来任务、目录外文件、错误 extent 会失败。
运算由 host 的 `tools/runner/cute_model_reference.py` 实现；生成器必须声明完整
依赖，不从本任务 golden 复制 reference。派生结果与哈希保留在 `calibration/`。

## 新增阶段后的验收

1. 先运行快速形状，检查 NumPy/QEMU 校准和 RTL 所有任务输出。
2. 检查编译器是否引入未声明向量栈写；先减少寄存器压力或明确工作区语义，不能
   用忽略未知 store 的方式使测试通过。
3. 运行原始形状，分别记录其结果；小形状通过不能代替原始形状。
4. 对关键生产者/消费者组合延迟 ack 与 marker 返回，再运行真实日志破坏测试。
5. 更新 [阶段表](workload-migration.md)、[状态](../reference/status.md) 与构建/运行清单。

每份运行包须保留 case 与输入身份、任务描述、两个 ELF 身份、QEMU 校准、完整 trace、
在线/离线报告和 host 退出状态。只截取“PASSED”字符串不构成验收。
