# 参与 DreamTravel

欢迎提交可复现的问题、轻量交互改进、数据适配器或测试。当前主要开发对象是 `DreamTravelMobile/` 中的 iOS App；`Sources/DreamTravelApp/` 是早期 macOS 原型。

1. Fork 仓库并创建分支。
2. 使用 Swift 6 和 Apple 原生框架，先沿用现有模块边界。
3. 运行 `zsh scripts/check-travel-pipeline.sh`、`zsh scripts/check-plan-themes.sh`、`zsh scripts/check-http-recovery.sh`。
4. 使用 Xcode 构建 iPhone 模拟器目标；界面改动附上不含个人信息的截图。
5. 暂存修改后运行 `zsh scripts/check-publication.sh`，再提交 PR。

请保持这些产品约定：

- 默认只展示必要信息；复杂选项按需展开。
- 地图和天气事实来自工具，不通过模型补写；缺失信息明确说明。
- 所有可切换候选及合适交通在发布前准备，完整校验后一次展示。
- 少于 8 分钟只提供步行，超过 15 分钟排除步行；测试需覆盖边界。
- 取消或失败保留上一份完整结果；用户点击不等于表达偏好。
- 不引入共享凭据，不将真实用户记录作为测试 Fixture。

描述 PR 时说明解决的问题、最终行为、验证结果和剩余限制。贡献按本仓库 MIT 许可证提供。
