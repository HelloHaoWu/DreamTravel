# 安全与隐私

开源仓库不提供任何可用 API Key、个人行程档案、开发者签名证书或测试账号。首次使用由使用者在 App 中配置自己的凭据。

- DeepSeek 与腾讯凭据保存在设备 Keychain；不写入源码、README、共享 Xcode Scheme 或用户偏好文件。
- 本地 `Validation/`、构建产物、Xcode `xcuserdata/`、`.env`、证书等不进入 Git。日志和截图仍可能包含地点、偏好或账号信息，提交前必须检查。
- 不在 Issue、PR、截图或网络日志中提交 Key、Authorization 头、含 Key 的请求 URL 或真实个人位置。
- 发布前运行 `zsh scripts/check-publication.sh`，检查 Git 暂存区和已提交历史。它是额外检查，不能代替人工审核。
- 发现自己的凭据泄漏时，先在对应服务商处撤销／轮换，再清理泄漏记录。

报告安全问题时，请使用仓库 Security 页的私密漏洞报告入口（如果可用）。不要在公开 Issue 中粘贴密钥或可利用的私人数据。

数据流与外部服务说明见 [隐私说明](Documentation/Privacy.md)。本仓库为开发中原型；没有经过独立安全审计。
