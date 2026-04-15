# RYKit

![Platform](https://img.shields.io/badge/Platform-iOS%2013.0%2B%20%7C%20macOS%2010.15%2B%20%7C%20tvOS%2013.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange)
![Version](https://img.shields.io/badge/Version-2.1.0-green)

[English](#english) | [中文](#中文)

A Swift foundational toolkit for Apple platforms, covering networking, resilient decoding, concurrency safety, and practical development utilities.

---

## Quick Start

### CocoaPods

```ruby
pod 'RYKit', :git => 'https://github.com/mithyer/RYKit.git', :tag => '2.1.0'
```

### Swift Package Manager

```swift
.package(url: "https://github.com/mithyer/RYKit.git", from: "2.1.0")
```

<a name="english"></a>
## English

A feature-rich Swift utility library providing common foundational modules for iOS, macOS, and tvOS applications.

### Version Information

- **Current Version**: 2.1.0
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
    .package(url: "https://github.com/mithyer/RYKit.git", from: "2.1.0")
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
pod 'RYKit/Core'
pod 'RYKit/NetworkHttp'
pod 'RYKit/NetworkStomp'
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
    businessCodeValidator: nil,
    handlers: handlers
)

request.response(User.self) { result in
    switch result {
    case .success(let user): print("User: \(user)")
    case .failure(let error): print("Error: \(error.localizedDescription)")
    }
}
```

#### STOMP Message Subscription Example
```swift
let manager = StompManager<YourChannel>(userToken: "user123")
let subscription = StompSubInfo(destination: "/topic/messages", identifier: "msg_subscriber", headers: nil)

let holder = manager.subscribe(
    dataType: Message.self,
    subscription: subscription,
    receiveMessageStrategy: .all
) { message, headers, raw in
    print("Received message: \(message)")
}
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

### Package and Module Mapping

Choose the public product that best fits your integration needs:

- `RYKit`: Umbrella product that re-exports `RYKitCore`, `RYKitNetworkHttp`, and `RYKitNetworkStomp`
- `RYKitCore`: Foundational utilities for decoding resilience, concurrency safety, lightweight storage, async helpers, logging, and common reusable building blocks.
  - `Associatable`: Attach associated objects to existing instances.
  - `Async`: Provide lightweight async execution helpers.
  - `Codable`: Improve resilient decoding and value conversion.
  - `Collections`: Offer linked lists, queues, weak maps, and weak sets.
  - `Combine`: Add practical Combine storage, callback throttling, and debouncing helpers.
  - `Extensions`: Add convenience helpers for common Foundation and Swift types.
  - `KV`: Simplify lightweight key-value storage and buffering.
  - `Lock`: Protect shared state in concurrent code.
  - `Log`: Persist and inspect runtime logs.
  - `Reachability`: Monitor shared network reachability state.
  - `TimeoutTask`: Manage delayed and timeout-based task execution.
- `RYKitNetworkHttp`: HTTP request abstraction and response handling
- `RYKitNetworkStomp`: STOMP-based real-time messaging over WebSocket

> In CocoaPods, the public subspecs are `Core`, `NetworkHttp`, and `NetworkStomp`. In Swift Package Manager, the corresponding public products are `RYKitCore`, `RYKitNetworkHttp`, and `RYKitNetworkStomp`.

### Typical Examples by Core Submodule

#### Associatable
```swift
final class Session: NSObject, Associatable {}
let session = Session()
session.setAssociated("traceId", value: "req-001")
let traceId: String? = session.associated("traceId")
```

#### Async
```swift
let executor = AsyncSerialExecutor()
try await executor.run {
    // run serial side effects
}
```

#### Codable
```swift
struct Profile: Codable {
    @Default.Empty<String> var name: String
    @Default.Zero<Int> var age: Int
}
```

```swift
struct Payload: Codable {
    @PreferValue var score: Int?
    @FromStringValue var amount: Double?
}
```

#### Collections
```swift
let queue = Queue<Int>()
queue.enqueue(1)
queue.enqueue(2)
let first = queue.dequeue()
```

```swift
let map = WeakMap<String, NSObject>()
let retainedObject = NSObject() // keep a strong owner outside the weak map
map.insert(key: "item", retainedObject)
let cached = map["item"]
```

#### Combine
```swift
var cancellables = Set<AnyCancellable>()
Just("value")
    .sink { value in print(value) }
    .store(in: &cancellables)
```

```swift
let debounce = DebounceCallback(interval: .milliseconds(300))
debounce.send {
    // execute once after quiet period
}
```

#### Extensions
```swift
let defaults = UserDefaults.WithKeyExtended { "app.\($0)" }
defaults.set("dark", forKey: "theme")
let theme = defaults.string(forKey: "theme")
```

#### KV
```swift
let kv = TinyKV(dbName: "app", tableName: "cache")
try await kv.set(value: "Alice", for: .string("user.name"))
let name: String = try await kv.getValue(for: .string("user.name"))
```

```swift
let buffered = TinyBufferedKV(dbName: "app", tableName: "buffer")
try await buffered.set(value: 42, for: .string("counter"))
try await buffered.flush()
```

#### Lock
```swift
class Store {
    @ThreadSafe var count: Int = 0
}
let store = Store()
store.$count.lock { $0 += 1 }
```

```swift
let lock = ReadWriteLock()
var value = 0
let current = lock.read { value }
lock.write { value = current + 1 }
```

#### Reachability
```swift
let token = GlobalReachability.shared.listen { status in
    print("network:", status)
}
```

#### TimeoutTask
```swift
let task = OnceTimeoutTask<String, Error>(
    flag: "load-profile",
    executionTimeoutInterval: .seconds(3),
    stopTimeoutInterval: .seconds(1),
    execute: { complete in
        complete(.success("ok"))
    },
    stopWhenExecuting: { stopped in
        stopped()
    }
)
```

```swift
let queue = OnceTimeoutTaskQueue<String, Error>(
    executeQueue: .main,
    defaultPreemptionStrategy: .waitCurrentCompletion
)
let cancellable = queue.taskDidFinish.sink { event in
    print(event.flag, event.doneType)
}
queue.addTask(task, priority: 10)
```

```swift
let persistentTask = OnceTimeoutTask<String, Error>(
    flag: "persistent",
    executionTimeoutInterval: nil,
    stopTimeoutInterval: nil,
    execute: { _ in
        // Complete later, or keep running.
    }
)
queue.addTask(persistentTask, priority: 1)
```

### License

MIT License

### Author

Ray - [GitHub](http://github.com/mithyer)

---

<a name="中文"></a>
## 中文

RYKit 是一个面向 Apple 平台的 Swift 基础能力工具库，重点覆盖网络通信、数据解码容错、并发安全以及常见开发工具场景，帮助你减少重复造轮子。

### 版本信息

- **当前版本**: 2.1.0
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
pod 'RYKit/Core'
pod 'RYKit/NetworkHttp'
pod 'RYKit/NetworkStomp'
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
    businessCodeValidator: nil,
    handlers: handlers
)

request.response(User.self) { result in
    switch result {
    case .success(let user): print("User: \(user)")
    case .failure(let error): print("Error: \(error.localizedDescription)")
    }
}
```

#### STOMP 消息订阅示例
```swift
let manager = StompManager<YourChannel>(userToken: "user123")
let subscription = StompSubInfo(destination: "/topic/messages", identifier: "msg_subscriber", headers: nil)

let holder = manager.subscribe(
    dataType: Message.self,
    subscription: subscription,
    receiveMessageStrategy: .all
) { message, headers, raw in
    print("收到消息: \(message)")
}
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

### 包与模块对应关系

根据接入方式选择最适合你的对外产品：

- `RYKit`：聚合产品，统一导出 `RYKitCore`、`RYKitNetworkHttp` 和 `RYKitNetworkStomp`
- `RYKitCore`：基础工具能力，重点覆盖解码容错、并发安全、轻量存储、异步辅助、日志以及常用可复用组件。
  - `Associatable`：为现有实例附加关联对象能力。
  - `Async`：提供轻量级异步执行辅助工具。
  - `Codable`：提升解码容错与数值转换能力。
  - `Collections`：提供链表、队列、弱引用映射和弱引用集合等数据结构。
  - `Combine`：补充实用的 Combine 存储、回调节流与防抖辅助能力。
  - `Extensions`：为常见 Foundation 和 Swift 类型补充便捷扩展能力。
  - `KV`：简化轻量级键值存储及缓冲写入。
  - `Lock`：用于在并发代码中保护共享状态。
  - `Log`：用于持久化和查看运行日志。
  - `Reachability`：用于监控共享网络可达性状态。
  - `TimeoutTask`：用于管理延时任务和超时任务。
- `RYKitNetworkHttp`：HTTP 请求封装与响应处理
- `RYKitNetworkStomp`：基于 WebSocket 的 STOMP 实时消息能力

> 在 CocoaPods 中，对外暴露的 subspec 为 `Core`、`NetworkHttp` 和 `NetworkStomp`；在 Swift Package Manager 中，对应的公开产品为 `RYKitCore`、`RYKitNetworkHttp` 和 `RYKitNetworkStomp`。

### 各子模块典型示例

#### Associatable
```swift
final class Session: NSObject, Associatable {}
let session = Session()
session.setAssociated("traceId", value: "req-001")
let traceId: String? = session.associated("traceId")
```

#### Async
```swift
let executor = AsyncSerialExecutor()
try await executor.run {
    // 串行执行副作用任务
}
```

#### Codable
```swift
struct Profile: Codable {
    @Default.Empty<String> var name: String
    @Default.Zero<Int> var age: Int
}
```

```swift
struct Payload: Codable {
    @PreferValue var score: Int?
    @FromStringValue var amount: Double?
}
```

#### Collections
```swift
let queue = Queue<Int>()
queue.enqueue(1)
queue.enqueue(2)
let first = queue.dequeue()
```

```swift
let map = WeakMap<String, NSObject>()
let object = NSObject()
map.insert(key: "item", object)
let cached = map["item"]
```

#### Combine
```swift
var cancellables = Set<AnyCancellable>()
Just("value")
    .sink { value in print(value) }
    .store(in: &cancellables)
```

```swift
let debounce = DebounceCallback(interval: .milliseconds(300))
debounce.send {
    // 静默窗口后触发一次
}
```

#### Extensions
```swift
let prefs = UserDefaults.WithKeyExtended { "app.\($0)" }
prefs.set("dark", forKey: "theme")
let theme = prefs.string(forKey: "theme")
```

#### KV
```swift
let kv = TinyKV(dbName: "app", tableName: "cache")
try await kv.set(value: "Alice", for: .string("user.name"))
let name: String = try await kv.getValue(for: .string("user.name"))
```

```swift
let buffered = TinyBufferedKV(dbName: "app", tableName: "buffer")
try await buffered.set(value: 42, for: .string("counter"))
try await buffered.flush()
```

#### Lock
```swift
class Store {
    @ThreadSafe var count: Int = 0
}
let store = Store()
store.$count.lock { $0 += 1 }
```

```swift
var value = 0
let lock = ReadWriteLock()
lock.write { value += 1 }
```

#### Reachability
```swift
let token = GlobalReachability.shared.listen { status in
    print("network:", status)
}
```

#### TimeoutTask
```swift
let task = OnceTimeoutTask<String, Error>(
    flag: "load-profile",
    executionTimeoutInterval: .seconds(3),
    stopTimeoutInterval: .seconds(1),
    execute: { complete in
        complete(.success("ok"))
    },
    stopWhenExecuting: { stopped in
        stopped()
    }
)
```

```swift
let queue = OnceTimeoutTaskQueue<String, Error>(
    executeQueue: .main,
    defaultPreemptionStrategy: .waitCurrentCompletion
)
let cancellable = queue.taskDidFinish.sink { event in
    print(event.flag, event.doneType)
}
queue.addTask(task, priority: 10)
```

```swift
let persistentTask = OnceTimeoutTask<String, Error>(
    flag: "persistent",
    executionTimeoutInterval: nil,
    stopTimeoutInterval: nil,
    execute: { _ in
        // Complete later, or keep running.
    }
)
queue.addTask(persistentTask, priority: 1)
```

### 许可证

MIT License

### 作者

Ray - [GitHub](http://github.com/mithyer)
