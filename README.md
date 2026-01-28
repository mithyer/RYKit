# RYKit

[English](#english) | [中文](#中文)

---

# HOW TO USE

```ruby
pod 'RYKit', :git => 'https://github.com/mithyer/RYKit.git', :tag => '2.0.7'
```

<a name="english"></a>
## English

A feature-rich Swift utility library providing common foundational modules for iOS, macOS, and tvOS applications.

### Version Information

- **Current Version**: 2.0.7
- **Supported Platforms**: iOS 13.0+, macOS 10.15+, tvOS 13.0+
- **Swift Version**: 5.0+

### Features Overview

RYKit provides the following core modules:

#### 📡 HTTP Request Module (`Http`)
Powerful HTTP network request wrapper offering:
- Support for GET, POST, and other HTTP methods
- Automatic data encryption/decryption (configurable)
- Flexible request strategies (cancel duplicate requests, debouncing)
- Support for multiple Content-Types (JSON, Form-Encoded)
- Comprehensive error handling and business code validation
- Automatic response parsing to models, lists, strings, etc.
- Support for custom headers and parameters
- Detailed request/response logging

#### 🔌 WebSocket/STOMP Module (`Stomp`)
Complete STOMP protocol implementation for real-time messaging:
- Automatic reconnection mechanism
- Subscription management and lifecycle control
- Message throttling strategy support
- Encrypted message support
- Thread-safe message dispatching
- Combine framework integration

#### 📝 Logging Module (`Log`)
Simple and easy-to-use logging tool:
- Automatic log file creation based on time
- Support for logging any Encodable type data
- Configurable write interval for same keys
- Asynchronous writing without blocking main thread
- JSON format storage for easy analysis

#### 🎁 Property Wrapper Module (`ValueWrapper`)
Multiple Property Wrappers to simplify Codable usage:

##### `@DefaultValue`
Automatically provide default values during decoding to avoid failures from missing fields:
```swift
struct User: Codable {
    @Default.StringEmpty var name: String
    @Default.IntZero var age: Int
    @Default.BoolFalse var isVIP: Bool
    @Default.ArrayEmpty var tags: [String]
}
```

Supported default value types:
- `BoolFalse` / `BoolTrue`
- `IntZero`
- `DoubleZero`
- `DecimalZero`
- `StringEmpty`
- `ArrayEmpty`
- `DicEmpty`

##### `@PreferValue`
Attempts to convert different types to target type, returns nil on failure:
```swift
struct Response: Codable {
    @PreferValue var count: Int?  // "123" auto-converts to 123
    @PreferValue var price: Double?  // 100 auto-converts to 100.0
}
```

##### `@IgnoreValue`
Marked properties are excluded from encoding/decoding:
```swift
struct Model: Codable {
    var id: String
    @IgnoreValue var tempData: String?  // Won't be encoded or decoded
}
```

#### 🔧 Extensions Module (`Extensions`)

##### Collection Extensions
```swift
let array = [1, 2, 3]
let emptyArray: [Int] = []
let result = emptyArray.nilIfEmpty  // nil

// SHA1 hash
let hash = "text".sha1
let dictHash = ["key": "value"].sha1
let arrayHash = ["a", "b", "c"].sha1

// Type conversion
let dict = ["age": 25]
let age: Int? = dict[(key: "age", type: Int.self)]
```

##### Number Extensions
```swift
let value: Int = 0
let result = value.nilIfZero  // nil
```

##### String Extensions
```swift
let str: String? = nil
let result = str.transferIfNil { "default" }  // "default"
```

#### 🌐 Network Reachability Module (`Capables/GlobalReachability`)
Monitor network status changes:
```swift
let listener = GlobalReachability.shared.listen { connection in
    switch connection {
    case .wifi:
        print("WiFi connected")
    case .cellular:
        print("Cellular connected")
    case .unavailable:
        print("Network unavailable")
    case .none:
        print("Unknown status")
    }
}
// Automatically stops listening when listener is released
```

#### 🔗 Associated Objects Module (`Capables/Associatable`)
Add associated properties to any class:
```swift
extension UIView: Associatable {}

// Usage
view.setAssociated("customID", value: "12345")
let id: String? = view.associated("customID", initializer: nil)
```

#### 🔒 Lock Module (`Lock`)
Thread synchronization primitives and property wrappers:

##### `UnfairLock`
High-performance lock based on `os_unfair_lock`:
```swift
let lock = UnfairLock()
lock.lock()
// Critical section
lock.unlock()

// Or use tryLock
if lock.tryLock() {
    // Critical section
    lock.unlock()
}
```

##### `ReadWriteLock`
Read-write lock allowing multiple readers or single writer:
```swift
let rwLock = ReadWriteLock()

// Read operation (multiple readers allowed)
rwLock.read {
    // Read shared data
}

// Write operation (exclusive access)
rwLock.write {
    // Modify shared data
}
```

##### `@ThreadSafe`
Property wrapper for thread-safe value access:
```swift
class Counter {
    @ThreadSafe var count: Int = 0

    func increment() {
        // Atomic access
        $count.lock { value in
            value += 1
        }
    }
}
```

##### `@RWThreadSafe`
Property wrapper using read-write lock for optimized concurrent reads:
```swift
class Cache {
    @RWThreadSafe var data: [String: Any] = [:]

    func read(key: String) -> Any? {
        $data.read { dict in
            dict[key]
        }
    }

    func write(key: String, value: Any) {
        $data.write { dict in
            dict[key] = value
        }
    }
}
```

#### 📦 Collections Module (`Collections`)
Thread-safe and non-thread-safe data structures:

##### `LinkedList` / `ThreadSafeLinkedList`
Doubly linked list implementation:
```swift
let list = LinkedList<Int>()
list.append(1)
list.append(2)
list.prepend(0)
list.insert(3, at: 2)

print(list.head)  // 0
print(list.tail)  // 2
print(list.count) // 4

_ = list.removeHead()
_ = list.remove(at: 1)
```

##### `Queue` / `ThreadSafeQueue`
FIFO queue based on linked list:
```swift
let queue = Queue<String>()
queue.enqueue("first")
queue.enqueue("second")

print(queue.front)  // "first"
print(queue.back)   // "second"

let item = queue.dequeue()  // "first"
```

#### ⏱ Timeout Task Module (`TimeoutTask`)
Task execution with timeout support:

##### `OnceTimeoutTask`
Single execution task with timeout:
```swift
let task = OnceTimeoutTask<String, Error>(
    timeoutInterval: .seconds(5),
    execute: { completed in
        // Perform async operation
        someAsyncOperation { result in
            completed(.success(result))
        }
    },
    done: { doneType in
        switch doneType {
        case .timeout:
            print("Task timed out")
        case .completed(let result):
            switch result {
            case .success(let value):
                print("Success: \(value)")
            case .failure(let error):
                print("Error: \(error)")
            }
        }
    }
)

task.perform(by: .main, timeoutQueue: .global())
```

##### `OnceTimeoutTaskQueue`
Queue for sequential timeout task execution:
```swift
let taskQueue = OnceTimeoutTaskQueue<Data, Error>(executeQueue: .main)

// Tasks execute sequentially, each with its own timeout
taskQueue.addTask(task1)
taskQueue.addTask(task2)
taskQueue.addTask(task3)

// Control queue execution
taskQueue.pause()
taskQueue.resume()
```

#### 🛠 Core Utilities
```swift
// Version comparison
let result = RYKit.compareVersion("1.2.3", "1.2.0")
// Returns: 1 (first version newer), 0 (same), -1 (second version newer)

// Get library version
let version = RYKit.version
```

### Installation

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

一个功能丰富的 Swift 工具库，为 iOS、macOS 和 tvOS 应用提供常用的基础功能模块。

### 版本信息

- **当前版本**: 2.0.7
- **支持平台**: iOS 13.0+, macOS 10.15+, tvOS 13.0+
- **Swift 版本**: 5.0+

### 功能概览

RYKit 提供了以下核心模块:

#### 📡 HTTP 请求模块 (`Http`)
功能强大的 HTTP 网络请求封装，提供:
- 支持 GET、POST 等多种请求方法
- 自动加密/解密数据（可配置）
- 灵活的请求策略（取消重复请求、防抖）
- 支持多种 Content-Type（JSON、Form-Encoded）
- 完善的错误处理和业务码校验
- 自动解析响应数据到模型、列表、字符串等
- 支持自定义请求头和参数
- 详细的请求/响应日志记录

#### 🔌 WebSocket/STOMP 模块 (`Stomp`)
完整的 STOMP 协议实现，用于实时消息通信:
- 自动重连机制
- 订阅管理和生命周期控制
- 支持消息节流（throttle）策略
- 支持加密消息
- 线程安全的消息分发
- Combine 框架集成

#### 📝 日志记录模块 (`Log`)
简单易用的日志记录工具:
- 按时间自动创建日志文件
- 支持记录任意 Encodable 类型的数据
- 可配置相同 key 的写入时间间隔
- 异步写入，不阻塞主线程
- JSON 格式存储，便于分析

#### 🎁 属性包装器模块 (`ValueWrapper`)
提供多种 Property Wrapper 简化 Codable 使用:

##### `@DefaultValue`
解码时自动提供默认值，避免因缺少字段导致解码失败:
```swift
struct User: Codable {
    @Default.StringEmpty var name: String
    @Default.IntZero var age: Int
    @Default.BoolFalse var isVIP: Bool
    @Default.ArrayEmpty var tags: [String]
}
```

支持的默认值类型:
- `BoolFalse` / `BoolTrue`
- `IntZero`
- `DoubleZero`
- `DecimalZero`
- `StringEmpty`
- `ArrayEmpty`
- `DicEmpty`

##### `@PreferValue`
尝试将不同类型转换为目标类型，转换失败则为 nil:
```swift
struct Response: Codable {
    @PreferValue var count: Int?  // "123" 会自动转换为 123
    @PreferValue var price: Double?  // 100 会自动转换为 100.0
}
```

##### `@IgnoreValue`
标记的属性不参与编码/解码:
```swift
struct Model: Codable {
    var id: String
    @IgnoreValue var tempData: String?  // 不会被编码或解码
}
```

#### 🔧 扩展模块 (`Extensions`)

##### Collection 扩展
```swift
let array = [1, 2, 3]
let emptyArray: [Int] = []
let result = emptyArray.nilIfEmpty  // nil

// SHA1 哈希
let hash = "text".sha1
let dictHash = ["key": "value"].sha1
let arrayHash = ["a", "b", "c"].sha1

// 类型转换
let dict = ["age": 25]
let age: Int? = dict[(key: "age", type: Int.self)]
```

##### Number 扩展
```swift
let value: Int = 0
let result = value.nilIfZero  // nil
```

##### String 扩展
```swift
let str: String? = nil
let result = str.transferIfNil { "default" }  // "default"
```

#### 🌐 网络可达性模块 (`Capables/GlobalReachability`)
监听网络状态变化:
```swift
let listener = GlobalReachability.shared.listen { connection in
    switch connection {
    case .wifi:
        print("WiFi 已连接")
    case .cellular:
        print("蜂窝网络已连接")
    case .unavailable:
        print("网络不可用")
    case .none:
        print("未知状态")
    }
}
// listener 释放后自动停止监听
```

#### 🔗 关联对象模块 (`Capables/Associatable`)
为任意类添加关联属性:
```swift
extension UIView: Associatable {}

// 使用
view.setAssociated("customID", value: "12345")
let id: String? = view.associated("customID", initializer: nil)
```

#### 🔒 锁模块 (`Lock`)
线程同步原语和属性包装器:

##### `UnfairLock`
基于 `os_unfair_lock` 的高性能锁:
```swift
let lock = UnfairLock()
lock.lock()
// 临界区
lock.unlock()

// 或使用 tryLock
if lock.tryLock() {
    // 临界区
    lock.unlock()
}
```

##### `ReadWriteLock`
读写锁，允许多个读取者或单个写入者:
```swift
let rwLock = ReadWriteLock()

// 读操作（允许多个读取者）
rwLock.read {
    // 读取共享数据
}

// 写操作（独占访问）
rwLock.write {
    // 修改共享数据
}
```

##### `@ThreadSafe`
线程安全值访问的属性包装器:
```swift
class Counter {
    @ThreadSafe var count: Int = 0

    func increment() {
        // 原子访问
        $count.lock { value in
            value += 1
        }
    }
}
```

##### `@RWThreadSafe`
使用读写锁优化并发读取的属性包装器:
```swift
class Cache {
    @RWThreadSafe var data: [String: Any] = [:]

    func read(key: String) -> Any? {
        $data.read { dict in
            dict[key]
        }
    }

    func write(key: String, value: Any) {
        $data.write { dict in
            dict[key] = value
        }
    }
}
```

#### 📦 集合模块 (`Collections`)
线程安全和非线程安全的数据结构:

##### `LinkedList` / `ThreadSafeLinkedList`
双向链表实现:
```swift
let list = LinkedList<Int>()
list.append(1)
list.append(2)
list.prepend(0)
list.insert(3, at: 2)

print(list.head)  // 0
print(list.tail)  // 2
print(list.count) // 4

_ = list.removeHead()
_ = list.remove(at: 1)
```

##### `Queue` / `ThreadSafeQueue`
基于链表的 FIFO 队列:
```swift
let queue = Queue<String>()
queue.enqueue("first")
queue.enqueue("second")

print(queue.front)  // "first"
print(queue.back)   // "second"

let item = queue.dequeue()  // "first"
```

#### ⏱ 超时任务模块 (`TimeoutTask`)
支持超时的任务执行:

##### `OnceTimeoutTask`
带超时的单次执行任务:
```swift
let task = OnceTimeoutTask<String, Error>(
    timeoutInterval: .seconds(5),
    execute: { completed in
        // 执行异步操作
        someAsyncOperation { result in
            completed(.success(result))
        }
    },
    done: { doneType in
        switch doneType {
        case .timeout:
            print("任务超时")
        case .completed(let result):
            switch result {
            case .success(let value):
                print("成功: \(value)")
            case .failure(let error):
                print("错误: \(error)")
            }
        }
    }
)

task.perform(by: .main, timeoutQueue: .global())
```

##### `OnceTimeoutTaskQueue`
顺序执行超时任务的队列:
```swift
let taskQueue = OnceTimeoutTaskQueue<Data, Error>(executeQueue: .main)

// 任务顺序执行，每个任务有独立的超时
taskQueue.addTask(task1)
taskQueue.addTask(task2)
taskQueue.addTask(task3)

// 控制队列执行
taskQueue.pause()
taskQueue.resume()
```

#### 🛠 核心工具
```swift
// 版本比较
let result = RYKit.compareVersion("1.2.3", "1.2.0")
// 返回: 1 (第一个版本更新), 0 (相同), -1 (第二个版本更新)

// 获取库版本
let version = RYKit.version
```

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
