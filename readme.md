# CUTE SDK 文档

这套文档是给第一次接触 CUTE 软硬件开发的人写的。

它不是只给熟手看的实现笔记，也不是把代码接口平铺出来的 API 手册。更重要的目标是先帮读者回答几个最基本的问题：

- CUTE 到底是什么，和我熟悉的 CUDA、cuBLAS、PyTorch reference、单元测试分别像什么。
- `cute-sdk` 在整个仓库里负责什么。
- 我平时会接触到的 `test.c`、`case.json`、suite YAML、golden、trace、memverify 是怎么串起来的。
- 当一个 case pass 或 fail 的时候，我应该怎么看，应该先怀疑哪里。

## 适合谁看

默认读者是：

- 没做过 CUTE 软硬件开发。
- 可能熟悉 C/C++、Python、CUDA、NumPy/PyTorch、单元测试或者硬件仿真中的一部分。
- 需要先把现有测试跑起来，再逐步理解 runtime、tensor、primitive、fusion、layer 的实现。

## 推荐阅读顺序

1. `首页`
2. `从熟悉概念理解 CUTE`
3. `第一次上手`
4. `测试相关`
5. `SDK 实现`

这个顺序的核心思路是：

- 先建立心智模型。
- 再学会跑测试和看结果。
- 最后才进入代码实现细节。

## 本地预览

```bash
cd /root/opencute/CUTE/doc/sdk-doc
env NO_MKDOCS_2_WARNING=true /root/opencute/CUTE/doc/design-doc/.venv/bin/mkdocs build
python3 -m http.server 8010 --bind 127.0.0.1 -d site
```

浏览器访问：

```text
http://127.0.0.1:8010
```
