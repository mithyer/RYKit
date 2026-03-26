# TinyBufferedKV Debounce Flush Timer 设计说明

## 背景
当前 `TinyBufferedKV` 使用常驻 repeating timer，即使缓冲区为空也会周期唤醒。目标是改为按写入触发的 debounce 机制，减少空转唤醒并保持现有对外 API 不变。

## 目标
- 保持 `TinyBufferedKV` 对外 API 不变。
- 定时刷新语义改为 debounce：最后一次写入后等待 `flushInterval` 再触发一次。
- `flush()` 后若无新数据，不保留活动 timer。
- 定时触发 `flush` 失败时仅记录，不断言、不自动重试；等待后续写入重新调度。

## 非目标
- 不修改 `TinyKV`。
- 不引入新的错误类型或对外回调。
- 不改变阈值触发（items/bytes）立即 flush 的行为。

## 方案选择
采用 **方案 A：单次 timer + 每次写入重建**。

### 选择理由
- 语义直接对应 debounce，行为最清晰。
- 与当前实现兼容性最好，改动集中在 `TinyBufferedKV` 内部。
- 维护成本低，出现问题时易定位。

## 行为定义
1. `flushInterval == 0`：不启用定时刷新。
2. 每次 `set(data:for:)` 后：
   - 若触达阈值（item/bytes）：立即 `flush()`。
   - 否则：重置一次性 timer 到 `now + flushInterval`。
3. timer 到点后执行 `flush()`。
4. timer 触发的 `flush()` 失败：记录日志并结束本次触发。
5. 后续只在新的 `set` 到来时重新调度 timer。

## 实现设计
文件：`Classes/KV/TinyBufferedKV.swift`

### 状态
- 保留：
  - `buffer`
  - `bufferedBytes`
  - `queue`
  - `timerQueue`
  - `flushTimer`
- 删除“初始化即常驻 repeating”语义。

### 新/改方法
1. `scheduleDebouncedFlushIfNeeded()`
   - 当 `flushInterval > 0` 时执行。
   - 取消旧 timer（若有）。
   - 创建 one-shot timer，deadline 为 `now + flushInterval`。
   - 到点后 `Task` 调用 `flush()`。
   - 失败路径：记录日志，返回。

2. `cancelFlushTimer()`
   - 统一关闭并置空 `flushTimer`。
   - 供 `flush()`、`deinit`、重建 timer 时复用。

3. `set(data:for:)`
   - 现有阈值逻辑保持不变。
   - `shouldFlush == false` 时调用 `scheduleDebouncedFlushIfNeeded()`。

4. `flush()`
   - 进入 `flush` 时先取消已有 timer（避免旧 timer 在落盘过程中重复触发）。
   - 空快照直接返回。
   - 非空快照按现有逻辑逐条写入 `TinyKV`。

5. `deinit`
   - 调用 `cancelFlushTimer()`。

## 并发与一致性
- buffer 读写继续只在 `queue` 上进行，保持串行一致性。
- timer 创建/取消统一通过 `timerQueue` 串行化，降低 cancel/recreate 竞态风险。
- `flush()` 空缓冲返回，保持幂等。

## 失败语义
- 主动调用 `flush()` 的失败：继续 `throws` 给调用方（不变）。
- timer 触发的失败：仅内部记录，不中断对象生命周期，不自动重试。

## 测试设计（TDD）
文件：`Project/RYKitTests/TinyBufferedKVTests.swift`

新增测试：
1. `test_debounceFlush_onlyAfterInterval()`
   - 配置非零 `flushInterval`。
   - 写入后立即用 `TinyKV` 读取应 notFound。
   - 等待超过 interval 后应可读到。

2. `test_debounceFlush_isResetBySubsequentSet()`
   - 连续两次写入，间隔小于 interval。
   - 在第一次理论触发点读取应仍不可见。
   - 在第二次写入后的 interval 后应可见。

保留并继续通过现有测试：
- 单键读缓冲。
- 阈值触发自动 flush。
- range 查询前 flush 一致性。
- 并发 set/flush 无丢更新。

## 风险与缓解
- 风险：timer 生命周期管理错误导致悬挂或重复触发。
  - 缓解：统一通过 `cancelFlushTimer()` 管理并在关键路径复用。
- 风险：时间相关测试偶发抖动。
  - 缓解：测试中使用明显大于 interval 的等待窗口，避免边界时间断言。

## 验收标准
- 非零 `flushInterval` 下，不再出现“空缓冲仍周期唤醒”的常驻 repeating 行为。
- debounce 行为与定义一致。
- 定时 flush 失败不触发断言，仅记录。
- 现有 `TinyBufferedKVTests` 全部通过。
