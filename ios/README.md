# TeslaMate iOS

原生 SwiftUI 客户端，最低支持 iOS 17。

第二轮加入多车切换、行程与充电列表、日期筛选、路线和功率曲线。
历史页面需要配套升级后端，见 [接口约定](docs/MOBILE_API.md) 和 [升级记录](UPGRADE_NOTES.md)。

## GitHub 自动编译

进入仓库的 **Actions → Build iOS IPA → Run workflow**。完成后在该次运行页面底部的
**Artifacts** 下载 `TeslaMate-iOS17-unsigned-…`，解压后得到 IPA。

该产物未使用 Apple 开发者证书签名，适用于 TrollStore 等自行管理签名的安装方式；
常规 iPhone 安装请在 Xcode 中选择自己的 Team 后编译。

## 在 Mac 上打开

1. 安装 Xcode 15 或更新版本。
2. 安装 XcodeGen：`brew install xcodegen`
3. 在本目录运行 `xcodegen generate`。
4. 打开 `TeslaMateMobile.xcodeproj`，选择自己的签名团队后运行。

App 初次启动时填写自己的服务器地址和 `MOBILE_API_TOKEN` 访问令牌。推荐 HTTPS；
使用 Tailscale 私网 HTTP 地址时先连接 Tailscale，不要将服务直接暴露到公网。
新连接验证成功且钥匙串保存成功后才替换当前连接。连接失败保留原配置。

## 测试

在 `ios` 目录生成工程后，在 Xcode 中选择 iPhone 模拟器并执行 Product → Test。
命令行可先运行 `xcrun simctl list devices available`，然后执行：

```bash
xcodebuild test -project TeslaMateMobile.xcodeproj -scheme TeslaMateMobile \
  -destination 'platform=iOS Simulator,id=<模拟器 UUID>' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES
```

仓库根目录 `.github/workflows/build-ios.yml` 会在 iOS 相关 PR、main 推送及手动触发时
先执行 XCTest，再构建未签名 IPA。失败日志和测试结果会作为 Artifacts 保存。

测试覆盖连接失败保留配置、切换服务器时的旧响应、退出与取消、钥匙串写入失败、
地址校验及 API 请求和解码。真机上仍需检查钥匙串、Tailscale、前后台切换和地图。

首页的“上次获取”指 App 收到服务器响应的本机时间，不代表车辆采样时间。
当前 API 没有车辆采样时间字段，因此界面明确提示该时间未知。
刷新失败保留上次数据并显示错误；重新打开 App 后仍需连接服务器获取数据。

## TrollStore IPA

在 Xcode 中选择 Generic iOS Device 并执行 Archive。导出 IPA 时使用你的可用签名配置，再通过 TrollStore 安装。请只在自己拥有和控制的设备上使用。

## 0.3.0 历史车辆模式

车辆页面右上角 → 历史车辆模式。适用于已出售或不再需要实时状态的车辆：
首页提供历史行程和充电入口，隐藏实时电量、位置与车锁。
设置按服务器地址和车辆 ID 保存在本机，重新连接同一服务器后保留，可随时关闭。
该设置不会停止服务器采集或删除记录；离线、休眠和采集失败不会自动开启此模式。
服务器请求失败仍会明确提示。此版本沿用 0.2.0 的历史接口，无需再次升级后端。

## 0.3.1 全屏路线

在行程详情点击「全屏查看路线」，可缩放、拖动地图，并点击「显示完整路线」重新取景。
右上角「关闭」返回详情，保留详情地图原视角。无有效坐标时不显示入口；单点记录只显示记录位置。
全屏页面继续使用苹果 MapKit，并保留长行程抽样说明。

## 0.4.0 界面升级

统一车辆主卡、累计统计、最近记录、月份分组列表、详情摘要和独立设置页。
深色模式跟随系统，大字体下指标自动单列排列。历史首页统计只包含已结束记录。
后端统计响应新增 car_id、scope 和数值记录数量，旧接口缺少数量时累计里程/补能显示横线。
调试构建的 UI 自动测试使用合成数据与隔离网络会话，不连接生产服务器；此入口不编译进 Release。
