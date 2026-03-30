# RYKit

![Platform](https://img.shields.io/badge/Platform-iOS%2013.0%2B%20%7C%20macOS%2010.15%2B%20%7C%20tvOS%2013.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange)
![Version](https://img.shields.io/badge/Version-2.0.9-green)

[English](#english) | [中文](#中文)

A Swift foundational toolkit for Apple platforms, covering networking, resilient decoding, concurrency safety, and practical development utilities.

---

## Quick Start

### CocoaPods

```ruby
pod 'RYKit', :git => 'https://github.com/mithyer/RYKit.git', :tag => '2.0.9'
```

### Swift Package Manager

```swift
.package(url: "https://github.com/mithyer/RYKit.git", from: "2.0.9")
```

<a name="english"></a>
## English

A feature-rich Swift utility library providing common foundational modules for iOS, macOS, and tvOS applications.

### Version Information

- **Current Version**: 2.0.9
- **Supported Platforms**: iOS 13.0+, macOS 10.15+, tvOS 13.0+
- **Swift Version**: 5.0+

### Features Overview

RYKit is a Swift foundational toolkit for Apple platforms, focused on providing stable, reusable building blocks for networking, data decoding, concurrency safety, and common utility scenarios.

Core capabilities at a glance:

- **HTTP request abstraction**: Encapsulates common request flows, response parsing, request strategies, and business error handling to reduce repetitive networking code.
- **STOMP real-time messaging**: Provides subscription management, reconnect handling, and message distribution for WebSocket-based real-time communication.
- **Codable resilience tools**: Uses property wrappers such as `@Default`, `@PreferValue`, and `@IgnoreValue` to make model decoding more fault-tolerant and easier to maintain.
- **Thread safety primitives**: Includes locks and thread-safe property wrappers for protecting shared state in concurrent code.
- **Practical utilities and data structures**: Offers common extensions, linked lists, queues, timeout task helpers, and version comparison utilities for everyday development.

Additional built-in modules include logging, network reachability monitoring, and associated object helpers. Detailed examples and module-specific usage are provided in the sections below.

### Installation

#### Swift Package Manager
Add `RYKit` to your Package.swift dependencies:

```swift
.dependencies([
    .package(url: "https://github.com/mithyer/RYKit.git", from: "2.0.9")
])
```

Then choose the product that fits your use case:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "RYKit", package: "RYKit")
    ]
)
```

Available products:
- `RYKit`: Aggregated product that re-exports `RYKitCore`, `RYKitNetworkHttp`, and `RYKitNetworkStomp`
- `RYKitCore`: Core utilities and foundational types
- `RYKitNetworkHttp`: HTTP request module
- `RYKitNetworkStomp`: STOMP messaging module

Import examples:

```swift
import RYKit                // Recommended: aggregated import
// or
import RYKitCore
import RYKitNetworkHttp
import RYKitNetworkStomp
```

#### CocoaPods
Add to your `Podfile`:

```ruby
# Install all modules
pod 'RYKit'

# Or install only needed submodules
# Network modules
pod 'RYKit/Network'

# Base modules
pod 'RYKit/Base'
```

Then run:
```bash
pod install
```

### Usage Examples

#### HTTP Request Example
```swift
let request = HttpRequest(
    session: .shared,
    queue: .main,
    baseURL: "https://api.example.com",
    method: .POST,
    path: "/users",
    params: .dic(["name": "John"]),
    contentType: .applicationJson,
    requestStrategy: .cancelIfRequesting,
    baseHeaders: ["Authorization": "Bearer token"],
    handlers: handlers
)

// Request object
request.response(User.self) { result in
    switch result {
    case .success(let user):
        print("User: \(user)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}

// Request list
request.response([User].self) { result in
    // Handle user list
}
```

#### STOMP Message Subscription Example
```swift
let manager = StompManager<YourChannel>(userToken: "user123")

let subscription = StompSubInfo(
    destination: "/topic/messages",
    identifier: "msg_subscriber",
    headers: nil
)

let holder = manager.subscribe(
    dataType: Message.self,
    subscription: subscription,
    receiveMessageStrategy: .all
) { message, headers, raw in
    print("Received message: \(message)")
}

// Automatically unsubscribes when holder is released
```

#### Logging Example
```swift
// Log string
LogRecorder.shared.saveLog(content: "App launched", key: "app_lifecycle")

// Log object
struct UserAction: Codable {
    let action: String
    let userId: Int
}
let action = UserAction(action: "login", userId: 12345)
LogRecorder.shared.saveLog(content: action, key: "user_action")

// Use interval limit (at least 60 seconds)
LogRecorder.shared.saveLog(
    content: "Button tapped", 
    key: "button_tap", 
    minIntervalBetweenSameKey: 60
)

// Get log file path
if let path = LogRecorder.shared.getCurrentLogFilePath() {
    print("Log file: \(path)")
}
```

### Module Description

Each submodule can be used independently, choose based on project needs:

| Module | Functionality | Dependencies |
|--------|---------------|--------------|
| `Network/Http` | HTTP network requests | None |
| `Network/Stomp` | WebSocket/STOMP messaging | Built-in SwiftStomp |
| `Base/Log` | Logging | None |
| `Base/Extensions` | Swift extensions | None |
| `Base/ValueWrapper` | Property wrappers | None |
| `Base/Capables` | Capability extensions | None |
| `Base/Lock` | Thread synchronization | None |
| `Base/Collections` | Data structures | Lock |
| `Base/TimeoutTask` | Timeout task management | Lock |

### License

MIT License

### Author

Ray - [GitHub](http://github.com/mithyer)

---

<a name="中文"></a>
## 中文

RYKit 是一个面向 Apple 平台的 Swift 基础能力工具库，重点覆盖网络通信、数据解码容错、并发安全以及常见开发工具场景，帮助你减少重复造轮子。

### 版本信息

- **当前版本**: 2.0.9
- **支持平台**: iOS 13.0+, macOS 10.15+, tvOS 13.0+
- **Swift 版本**: 5.0+

### 功能概览

核心能力包括：

- **HTTP 请求封装**：统一常见请求流程、响应解析、请求策略与业务错误处理，减少重复网络层代码。
- **STOMP 实时通信**：提供订阅管理、重连处理和消息分发能力，适合基于 WebSocket 的实时消息场景。
- **Codable 容错工具**：通过 `@Default`、`@PreferValue`、`@IgnoreValue` 等属性包装器，让模型解码更稳健、更易维护。
- **线程安全原语**：内置锁与线程安全属性包装器，便于在并发代码中保护共享状态。
- **常用扩展与数据结构**：提供常见扩展、链表、队列、超时任务工具和版本比较等高频基础能力。

此外，库中还内置了日志记录、网络可达性监听和关联对象等实用模块。更详细的示例和模块说明请继续查看下方章节。

### 安装

#### CocoaPods
在你的 `Podfile` 中添加:

```ruby
# 安装所有模块
pod 'RYKit'

# 或者只安装需要的子模块
# 网络模块
pod 'RYKit/Network/Http'
pod 'RYKit/Network/Stomp'

# 基础模块
pod 'RYKit/Base/Log'
pod 'RYKit/Base/Extensions'
pod 'RYKit/Base/ValueWrapper'
pod 'RYKit/Base/Capables'
pod 'RYKit/Base/Lock'
pod 'RYKit/Base/Collections'
pod 'RYKit/Base/TimeoutTask'
```

然后运行:
```bash
pod install
```

### 使用示例

#### HTTP 请求示例
```swift
let request = HttpRequest(
    session: .shared,
    queue: .main,
    baseURL: "https://api.example.com",
    method: .POST,
    path: "/users",
    params: .dic(["name": "John"]),
    contentType: .applicationJson,
    requestStrategy: .cancelIfRequesting,
    baseHeaders: ["Authorization": "Bearer token"],
    handlers: handlers
)

// 请求对象
request.response(User.self) { result in
    switch result {
    case .success(let user):
        print("User: \(user)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}

// 请求列表
request.response([User].self) { result in
    // 处理用户列表
}
```

#### STOMP 消息订阅示例
```swift
let manager = StompManager<YourChannel>(userToken: "user123")

let subscription = StompSubInfo(
    destination: "/topic/messages",
    identifier: "msg_subscriber",
    headers: nil
)

let holder = manager.subscribe(
    dataType: Message.self,
    subscription: subscription,
    receiveMessageStrategy: .all
) { message, headers, raw in
    print("收到消息: \(message)")
}

// holder 释放时自动取消订阅
```

#### 日志记录示例
```swift
// 记录字符串
LogRecorder.shared.saveLog(content: "应用启动", key: "app_lifecycle")

// 记录对象
struct UserAction: Codable {
    let action: String
    let userId: Int
}
let action = UserAction(action: "登录", userId: 12345)
LogRecorder.shared.saveLog(content: action, key: "user_action")

// 使用时间间隔限制（至少间隔 60 秒）
LogRecorder.shared.saveLog(
    content: "按钮点击", 
    key: "button_tap", 
    minIntervalBetweenSameKey: 60
)

// 获取日志文件路径
if let path = LogRecorder.shared.getCurrentLogFilePath() {
    print("日志文件: \(path)")
}
```

### 模块说明

每个子模块都可以独立使用，根据项目需求选择安装:

| 模块 | 功能 | 依赖 |
|------|------|------|
| `Network/Http` | HTTP 网络请求 | 无 |
| `Network/Stomp` | WebSocket/STOMP 消息 | 内置 SwiftStomp |
| `Base/Log` | 日志记录 | 无 |
| `Base/Extensions` | Swift 扩展 | 无 |
| `Base/ValueWrapper` | 属性包装器 | 无 |
| `Base/Capables` | 能力扩展 | 无 |
| `Base/Lock` | 线程同步 | 无 |
| `Base/Collections` | 数据结构 | Lock |
| `Base/TimeoutTask` | 超时任务管理 | Lock |

### 许可证

MIT License

### 作者

Ray - [GitHub](http://github.com/mithyer)
