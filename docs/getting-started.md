# 跑通第一组测试

先完成 OpenCUTE 根目录的 submodule 初始化及硬件/SDK 配置生成。工具链需要支持 RVV、Zfh/Zvfh 和裸机 HTIF；QEMU system 模式与 Verilator 各自使用对应启动、链接和平台代码。

## 编译 SDK

激活支持上述能力的工具环境后，在 OpenCUTE 根目录执行。编译器从 `PATH` 查找，
输出使用相对于仓库根目录的固定路径：

```bash
cmake -S cute-sdk -B ../opencute-out/sdk \
  -DCMAKE_C_COMPILER="$(command -v riscv-none-elf-gcc)" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
cmake --build ../opencute-out/sdk -j16
```

这一步验证源码可编译，不运行 RTL。需要 system 或模型测试时，使用对应构建入口生成 fixtures；不要手工复用另一组输入的 ELF。

## 选择验证流程

- 新增任务边界、内存依赖或模型阶段：使用 [system-level 验证](testing/system-verification.md)，先跑 `tests/system/case.json` 基线，再跑模型 case。
- 调试已有 primitive/fusion：参考 [suite](testing/suites.md) 和 [runner](testing/runner.md)。第一次运行应构建匹配配置的 simulator；`--skip-build` 仅用于已经确认产物匹配的开发环境。

不要把普通 Linux 用户态 QEMU 启动命令用于本流程的裸机 ELF。不要把旧 memverify 的 tolerance pass 等同于新流程的逐任务 byte-exact pass。验收前阅读 [当前状态](reference/status.md)。
