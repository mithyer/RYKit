# RYKit

一个功能丰富的 Swift 工具库，为 iOS、macOS 和 tvOS 应用提供常用的基础功能模块。

## 版本信息

- **当前版本**: 1.2.15
- **支持平台**: iOS 13.0+, macOS 10.15+, tvOS 13.0+
- **Swift 版本**: 5.0+

## 功能概览

RYKit 提供了以下核心模块：

### 📡 HTTP 请求模块 (`Http`)
功能强大的 HTTP 网络请求封装，提供：
- 支持 GET、POST 等多种请求方法
- 自动加密/解密数据（可配置）
- 灵活的请求策略（取消重复请求、防抖）
- 支持多种 Content-Type（JSON、Form-Encoded）
- 完善的错误处理和业务码校验
- 自动解析响应数据到模型、列表、字符串等
- 支持自定义请求头和参数
- 详细的请求/响应日志记录

### 🔌 WebSocket/STOMP 模块 (`Stomp`)
完整的 STOMP 协议实现，用于实时消息通信：
- 自动重连机制
- 订阅管理和生命周期控制
- 支持消息节流（throttle）策略
- 支持加密消息
- 线程安全的消息分发
- Combine 框架集成

### 📝 日志记录模块 (`Log`)
简单易用的日志记录工具：
- 按时间自动创建日志文件
- 支持记录任意 Encodable 类型的数据
- 可配置相同 key 的写入时间间隔
- 异步写入，不阻塞主线程
- JSON 格式存储，便于分析

### 🎁 属性包装器模块 (`ValueWrapper`)
提供多种 Property Wrapper 简化 Codable 使用：

#### `@DefaultValue`
解码时自动提供默认值，避免因缺少字段导致解码失败：
```swift
struct User: Codable {
    @Default.StringEmpty var name: String
    @Default.IntZero var age: Int
    @Default.BoolFalse var isVIP: Bool
    @Default.ArrayEmpty var tags: [String]
}
```

支持的默认值类型：
- `BoolFalse` / `BoolTrue`
- `IntZero`
- `DoubleZero`
- `DecimalZero`
- `StringEmpty`
- `ArrayEmpty`
- `DicEmpty`

#### `@PreferValue`
尝试将不同类型转换为目标类型，转换失败则为 nil：
```swift
struct Response: Codable {
    @PreferValue var count: Int?  // "123" 会自动转换为 123
    @PreferValue var price: Double?  // 100 会自动转换为 100.0
}
```

#### `@IgnoreValue`
标记的属性不参与编码/解码：
```swift
struct Model: Codable {
    var id: String
    @IgnoreValue var tempData: String?  // 不会被编码或解码
}
```

### 🔧 扩展模块 (`Extensions`)

#### Collection 扩展
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

#### Number 扩展
```swift
let value: Int = 0
let result = value.nilIfZero  // nil
```

#### String 扩展
```swift
let str: String? = nil
let result = str.transferIfNil { "default" }  // "default"
```

### 🌐 网络可达性模块 (`Capables/GlobalReachability`)
监听网络状态变化：
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

### 🔗 关联对象模块 (`Capables/Associatable`)
为任意类添加关联属性：
```swift
extension UIView: Associatable {}

// 使用
view.setAssociated("customID", value: "12345")
let id: String? = view.associated("customID", initializer: nil)
```

### 🛠 核心工具
```swift
// 版本比较
let result = RYKit.compareVersion("1.2.3", "1.2.0")
// 返回: 1 (第一个版本更新), 0 (相同), -1 (第二个版本更新)

// 获取库版本
let version = RYKit.version
```

## 安装

### CocoaPods
在你的 `Podfile` 中添加：

```ruby
# 安装所有模块
pod 'RYKit'

# 或者只安装需要的子模块
pod 'RYKit/Http'
pod 'RYKit/Stomp'
pod 'RYKit/Log'
pod 'RYKit/Extensions'
pod 'RYKit/ValueWrapper'
pod 'RYKit/Capables'
```

然后运行：
```bash
pod install
```

## 使用示例

### HTTP 请求示例
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

### STOMP 消息订阅示例
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

### 日志记录示例
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

## 模块说明

每个子模块都可以独立使用，根据项目需求选择安装：

| 模块 | 功能 | 依赖 |
|------|------|------|
| `Http` | HTTP 网络请求 | 无 |
| `Stomp` | WebSocket/STOMP 消息 | 内置 SwiftStomp |
| `Log` | 日志记录 | 无 |
| `Extensions` | Swift 扩展 | 无 |
| `ValueWrapper` | 属性包装器 | 无 |
| `Capables` | 能力扩展 | 无 |

## 许可证

MIT License

## 作者

Ray - [GitHub](http://github.com/mithyer)

