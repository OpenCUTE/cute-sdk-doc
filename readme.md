# CUTE SDK 文档

源文档在 `docs/`，站点配置为 `mkdocs.yml`。从 OpenCUTE 根目录运行：

```bash
python3 -m pip install -r doc/requirements.txt
python3 tools/docs/build_docs.py --out /tmp/opencute-docs
python3 -m http.server 8010 --directory /tmp/opencute-docs
```

访问 `/sdk/`；主文档在 `/`，硬件设计文档在 `/design/`。只预览 SDK 时运行 `python3 -m mkdocs serve -f doc/sdk-doc/mkdocs.yml`。构建结果与日志保存在指定输出目录及相邻日志目录，不提交生成的站点。

[主文档入口](../README.md) · [SDK 首页](docs/index.md) · [验收状态](docs/reference/status.md)
