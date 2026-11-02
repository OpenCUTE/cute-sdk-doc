# Runtime 实现

`cutelib/runtime/cute_runtime.h` 是 `cutelib` 的最低层 C API。它不关心 tensor tiling，也不关心 post-op，只负责把普通 C 参数翻译成 CUTE/YGJK 配置指令并提交宏指令。

## 文件位置

```text
cute-sdk/cutelib/runtime/cute_runtime.h
```

依赖：

```text
cuteisa/cute_isa_v1/instruction.h
```

`instruction.h` 提供底层宏：

```text
CUTE_CONFIG_TENSOR_A/B/C/D
CUTE_CONFIG_SCALE_A/B
CUTE_CONFIG_TENSOR_DIM
CUTE_CONFIG_CONV_PARAMS
CUTE_SEND_MACRO_INST
CUTE_QUERY_*
CUTE_CLEAR_INST
```

## Tile 常量

```c
#define CUTE_SCP_M 64
#define CUTE_SCP_N 64
```

runtime 默认按硬件 SCP tile 大小配置 matmul。上层 tensor tiling 也以 `64 x 64` 为基本 tile。

## Matmul Submit

### `cute_matmul`

```c
static inline uint64_t cute_matmul(
    const void *a, uint64_t a_stride,
    const void *b, uint64_t b_stride,
    void *bias, uint64_t bias_stride,
    void *d, uint64_t d_stride,
    uint64_t m, uint64_t n, uint64_t k,
    uint64_t element_type,
    uint64_t bias_mode,
    uint64_t transpose,
    uint64_t m_index)
```

调用顺序：

```text
CONFIG_TENSOR_A(a, a_stride)
CONFIG_TENSOR_B(b, b_stride)
CONFIG_TENSOR_C(bias, bias_stride)
CONFIG_TENSOR_D(d, d_stride)
CONFIG_TENSOR_DIM(m, n, k, 0)
CONFIG_CONV_PARAMS(element_type, bias_mode, transpose, ...)
SEND_MACRO_INST()
```

返回值是 task id，后续用 `cute_wait_task(task_id)` 等待完成。

`m_index` 写入 `CONFIG_CONV_PARAMS` 的 `ow_index` 字段，用于和硬件宏指令接口保持一致。当前 tensor 层大多数路径传 `0`。

### `cute_blockscale_matmul`

`cute_blockscale_matmul` 比 `cute_matmul` 多配置：

```text
CONFIG_SCALE_A(scale_a)
CONFIG_SCALE_B(scale_b)
```

用于 MXFP / block-scale matmul 路径。参数结构和普通 matmul 保持一致，便于 tensor 层统一封装。

## FIFO 查询

runtime 暴露非阻塞查询：

| API | 含义 |
|-----|------|
| `cute_query_finish()` | 返回已完成 task 的 bitmask |
| `cute_fifo_full()` | FIFO 是否已满 |
| `cute_fifo_info()` | FIFO 当前占用 bitmask |
| `cute_query_inst_tail()` | 查询已完成宏指令尾编号 |
| `cute_query_mem_read_count()` | 查询外部读次数 |
| `cute_query_mem_write_count()` | 查询外部写次数 |

## 等待与出队

```c
static inline void cute_wait_task(uint64_t task_id)
{
    uint64_t mask = 1UL << task_id;
    while (!(CUTE_QUERY_MACRO_INST_FINISH() & mask))
        ;
    CUTE_CLEAR_INST();
}
```

约束：

| 约束 | 原因 |
|------|------|
| wait/dequeue 必须按 issue 顺序调用 | `CUTE_CLEAR_INST()` 清队首 |
| 不能跳过中间 task | FIFO 是顺序出队 |
| 上层 pipeline 只能重叠 compute 和 post-op，不能乱序 drain | 硬件完成语义仍按 FIFO 管理 |

这也是 tensor 层 `cute_tiled_matmul_*` 的核心约束：每次 issue 下一个 tile 前，必须确保对应 scratch buffer 不会被覆盖。

## Runtime 测试

当前 runtime 层测试：

| Case | 说明 |
|------|------|
| `runtime_matmul_i8_128_128_128_zeroinit` | 基础 INT8 matmul |
| `runtime_matmul_i8_128_128_128_zeroinit_transpose` | transpose 输出路径 |
| `runtime_matmul_mxfp8e4m3_64_64_64_zeroinit` | MXFP/block-scale 路径 |
| `runtime_matmul_i8_tiled_128x128_fifo` | FIFO / tiled issue 基础验证 |

这些 case 主要验证 `instruction.h -> runtime wrapper -> hardware macro inst` 的基本链路。

## System checkpoint

`cutelib/runtime/cute_checkpoint.h` 在 runtime 之上提供：

| API | 调用责任与含义 |
|---|---|
| `cute_checkpoint_context` | 每 hart 私有，初始化为零，维护软件完成序号 |
| `cute_checkpoint(&context, key)` | pre-fence → TRACE_MARK → 消费返回 seq → post-fence；返回标记是否匹配 |
| `cute_checkpoint_finish()` | 最后标记后等待 512 个 CSR 周期，确保 trace 最终 watermark 有机会输出 |

checkpoint 不替调用者等待 CUTE 宏指令。先按 FIFO 顺序 `cute_wait_task`，再标记
软件任务完成。当前 profile 的 fence 排空此前 RVV 访存；MARK 时 host 要求该
hart 无 outstanding。必须检查 checkpoint 的返回值，不能只发一条无返回依赖
的 RoCC 指令就让 CPU 继续操作消费者 buffer。

`key` 是软件任务标签；TL source 是访存事务标签，二者不等价。一个软件任务
可以包含多个 CUTE tile 和 RVV 操作，最终一次比较全部声明输出。scale 与中间
workspace 也应有明确归属。详见 [case 接入](../testing/model-case.md)。

上述等待不通过 CPU 读回模型数据，也不模拟 UART 传输。最后的计时等待用于
日志完整性水位；它不能替代程序之前应执行的 wait/fence。
