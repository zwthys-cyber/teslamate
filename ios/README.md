# TeslaMate iOS

原生 SwiftUI 客户端，最低支持 iOS 17。

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

App 初次启动时填写服务器地址 `http://100.88.30.82:4000/` 和服务器生成的访问令牌。

## TrollStore IPA

在 Xcode 中选择 Generic iOS Device 并执行 Archive。导出 IPA 时使用你的可用签名配置，再通过 TrollStore 安装。请只在自己拥有和控制的设备上使用。
