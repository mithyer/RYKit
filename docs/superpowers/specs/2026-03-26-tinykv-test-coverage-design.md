# TinyKV / TinyBufferedKV 单元测试覆盖设计（风险优先 + 覆盖闭环）

- 日期：2026-03-26
- 范围：仅单元测试（不含集成、性能基准、长期 soak）
- 目标：在现有测试基础上补齐删除语义、查询异常、缓冲 flush 竞态与错误传播，形成高风险路径闭环

## 1. 设计结论

采用方案 A：**风险优先 + 覆盖闭环**。

优先级分层：
- **P0（高风险）**：删除语义、查询异常防护、flush 并发竞态、错误传播
- **P1（中风险）**：空输入/重复 key/极值边界、排序稳定性
- **P2（低风险）**：对称性与一致性补齐

## 2. 覆盖对象与职责边界

### TinyKV
关注点：
- 单 key 写读一致性（string/int）
- 范围查询四种选择器与升降序
- 删除语义（单 key / 范围 / 全量）
- 错误分支（notFound / decodeFailed / 非法 condition）

### TinyBufferedKV
关注点：
- 缓冲读优先（buffer > storage）
- flush 状态转换与触发路径（手动、阈值、定时）
- 强化并发（set/flush/getValues 交错）
- flush 错误传播（不吞错）

## 3. 数据流与状态转换

### TinyKV
- set(value/data) -> getValue/getData：数据一致
- getDatas/getValues(range)：四类 query key 一致性与排序方向
- remove/removeAll：删除后可见状态与计数一致

### TinyBufferedKV
- set -> buffer 立即可读
- buffer -> flush -> storage（手动 / 阈值 / 定时）
- getValues 触发 flush 后再查询，保证结果来自可持久状态
- 并发交错下保证：不丢数据、结果可解码、无非预期异常

## 4. 新增测试清单（可直接实现）

## 4.1 TinyKVTests.swift

### P0
1. test_remove_withStringKey_deletesOnlyTarget
2. test_remove_withIntKey_deletesOnlyTarget
3. test_remove_withRangeKey_stringLike_deletesMatchedOnly
4. test_remove_withRangeKey_intCondition_deletesMatchedOnly
5. test_removeAll_clearsCountAndAllKeys
6. test_getValue_whenDecodeTypeMismatch_throwsDecodeFailed
7. test_getValues_withIntCondition_emptyExpression_throws
8. test_getValues_withIntCondition_commentToken_throws
9. test_getValues_withIntCondition_semicolon_throws

### P1
10. test_getValues_withStringsIn_emptyList_returnsEmpty
11. test_getValues_withIntsIn_emptyList_returnsEmpty
12. test_getValues_withStringsIn_duplicateKeys_noDuplicateResults
13. test_getValues_withIntsIn_duplicateKeys_noDuplicateResults
14. test_getValues_withIntCondition_extremeBounds_returnsExpected
15. test_allKeys_afterMixedWritesAndDeletes_matchesPersistedState

### P2
16. test_getDatas_and_getValues_forSameRange_haveSameOrder
17. test_count_matchesInsertedMinusDeleted_forStringAndIntMixed

## 4.2 TinyBufferedKVTests.swift

### P0
1. test_remove_withBufferedValue_thenGet_throwsNotFoundAfterFlush
2. test_removeRange_whenBufferAndStorageBothHaveData_deletesConsistently
3. test_removeAll_clearsBufferAndStorage
4. test_concurrent_set_and_manualFlush_noLostUpdates
5. test_timerFlush_and_manualFlush_interleaving_keepsDataValid
6. test_getValues_duringConcurrentWrites_doesNotThrow_andReturnsDecodableSet

### P1
7. test_getData_prefersBufferOverStorage_beforeFlush
8. test_flush_idempotent_whenNoBufferedEntries
9. test_multipleRapidSets_sameKey_lastWriteWins_afterFlush
10. test_cancelledDebounce_onNewSet_onlySingleEffectiveFlush

### P2
11. test_count_beforeAndAfterFlush_matchesExpected
12. test_allKeys_afterBufferedDeletes_matchesStorageAfterFlush

## 5. 断言与测试风格约束

- 集合结果：分离验证“集合等价”和“排序方向”，避免单断言混淆失败原因
- 并发测试：不依赖精确时序，验证最终一致性与可解码性
- 异常测试：优先断言 TinyKV.Error 的具体 case，而非泛化 throws
- 每个用例只覆盖一个主要失败维度，避免多原因耦合

## 6. 实施顺序建议

1. 先落 TinyKV P0（删除 + condition 异常 + decodeFailed）
2. 再落 TinyBufferedKV P0（flush 竞态 + remove 语义）
3. 回补双方 P1/P2 做稳定性与对称性

## 7. 完成判定

满足以下条件即认为覆盖增强完成：
- P0 全部落地并通过
- 关键 API（set/get/query/remove/removeAll/count/allKeys/flush）均有正反路径
- 并发增强用例在本地重复执行无间歇性失败
