// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WeChat2AI", platforms: [.macOS(.v13)],
    products: [.library(name: "WeChat2AICore", targets: ["WeChat2AICore"]),
               .executable(name: "wechat2ai", targets: ["WeChat2AICLI"])],
    targets: [.systemLibrary(name: "CZlib"),
              .target(name: "WeChat2AICore", dependencies: ["CZlib"]),
              .executableTarget(name: "WeChat2AICLI", dependencies: ["WeChat2AICore"])])
