# Changelog

本项目的所有重要变更都会记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [已发布]

## [1.0.0] - 2026-08-17

### 新增

- 首次发布：一键启动 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web 界面的 Windows 桌面应用。
- 启动画面：DeepSeek 鲸鱼 Logo 与「初始化 / 定位 / 启动服务 / 打开界面」四步进度。
- 服务复用与单实例：重复启动只聚焦已有窗口，不重复启动服务。
- 退出清理：关闭窗口自动停止由本应用拉起的服务进程。
- 便携版（portable）与 NSIS 安装版构建脚本（`build.bat` / `build.ps1`），构建后自动嵌入 DeepSeek 鲸鱼图标与版本信息。
- 蓝鲸/黑鲸品牌图标及一键重新生成脚本（`scripts\build-icons.bat`）。
- 中英文 README 与 MIT 许可证。
