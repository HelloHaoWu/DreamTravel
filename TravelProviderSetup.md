# 配置自己的模型、地图与天气服务

默认使用自己的 DeepSeek API Key 和腾讯位置服务 WebService Key。开源版本不附带任何共享凭据或额度。

## App 内配置（推荐）

1. 打开设置 → 模型连接，输入自己的 DeepSeek Key，验证后保存。
2. 打开设置 → 我的腾讯位置服务，点击获取 Key，在手机默认浏览器完成[腾讯官方注册](https://lbs.qq.com/dev/console/quick-register)。
3. 将自己的 WebService Key 复制回 App。验证地点、路线和天气后保存到设备 Keychain。
4. 回到首页开始安排。替换地图 Key 后在下一次生成生效。

默认模型名是 `deepseek-v4-flash`；账号权限、服务端模型别名和接口可用性以验证结果为准。规划使用 Responses 接口，主动搜索使用 Anthropic 兼容接口的搜索能力。代码中的模型名不是凭据，也不保证任意账号均能调用。

腾讯 Key 需能调用城市解析、地点搜索、步行／骑行／驾车路线和天气接口。配额及付费规则以自己控制台为准，本仓库不保证免费额度。首屏结果包含全部可选交通；短于 8 分钟的连接只查步行，以减少不必要调用。

## 开发者：可选本地钥匙串联调

普通 App 使用不需要本节。以下服务名只是本机 Keychain 条目的标识，不包含凭据。

在 macOS 钥匙串访问工具中添加通用密码，或在 Terminal 运行交互命令。`-w` 后不写值，在提示时输入；不要将 Key 作为明文命令参数，也不要启用 shell 跟踪。

```bash
security add-generic-password -U \
  -s com.dreamtravel.test.tencent-map -a web-service -w

security add-generic-password -U \
  -s com.dreamtravel.test.deepseek -a api-key -w
```

编译模拟器 Debug App 后，`zsh scripts/run-mobile-live.sh` 从本地钥匙串读取腾讯开发 Key，并仅注入该次模拟器进程。普通 App 仍优先使用设置里保存的个人腾讯 Key。

真实调用检查：

```bash
# 地图短途策略；脚本需要本节的两个测试条目
zsh scripts/check-active-search-live.sh --transport-only

# 真实规划、搜索与地图链路（会产生 API 用量）
zsh scripts/check-active-search-live.sh
```

Debug 也支持开发进程环境变量 `DREAMTRAVEL_DEEPSEEK_API_KEY` 和 `DREAMTRAVEL_TENCENT_MAP_KEY`。不要把它们的值写入共享 Scheme、`.env`、源码、Issue 或版本库。Release 不读取这两个开发注入变量。

## 数据与发布边界

- 无凭据时可查看明确标注的演示行程，不会冒充真实查询。
- 腾讯地点数据不保证提供营业时间、价格、预约库存；公开资料补充也需保留来源和时效边界。
- 本地真实联调会生成诊断记录，可能含真实地点和个人描述。`Validation/`、构建目录、Xcode 用户目录及证书均排除在 Git 外。
- 用户各自配置 Key 的原型，与运营方共享凭据的公共产品是两种部署方式。若后续使用运营方 Key，应在服务端网关保管并限流，不将共享 Key 打包进 App。
- 分享代码前运行 `zsh scripts/check-publication.sh`；此检查不替代人工审阅。

相关实现与数据流：[架构](Documentation/Architecture.md) · [隐私](Documentation/Privacy.md) · [安全](SECURITY.md)。
