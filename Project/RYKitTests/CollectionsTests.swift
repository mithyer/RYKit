//
//  CollectionsTests.swift
//  RYKitTests
//
//  Created by Claude on 2026/1/21.
//

import XCTest
@testable import RYKit

// MARK: - LinkedList Tests

final class LinkedListTests: XCTestCase {

  func test_init_isEmpty() {
      let list = LinkedList<Int>()
      XCTAssertTrue(list.isEmpty)
      XCTAssertEqual(list.count, 0)
      XCTAssertNil(list.head)
      XCTAssertNil(list.tail)
  }

  func test_prepend_addsToHead() {
      let list = LinkedList<Int>()
      list.prepend(1)
      list.prepend(2)

      XCTAssertEqual(list.head, 2)
      XCTAssertEqual(list.tail, 1)
      XCTAssertEqual(list.count, 2)
  }

  func test_append_addsToTail() {
      let list = LinkedList<Int>()
      list.append(1)
      list.append(2)

      XCTAssertEqual(list.head, 1)
      XCTAssertEqual(list.tail, 2)
      XCTAssertEqual(list.count, 2)
  }

  func test_insert_atMiddle() {
      let list = LinkedList<Int>()
      list.append(1)
      list.append(3)
      list.insert(2, at: 1)

      XCTAssertEqual(list.value(at: 0), 1)
      XCTAssertEqual(list.value(at: 1), 2)
      XCTAssertEqual(list.value(at: 2), 3)
      XCTAssertEqual(list.count, 3)
  }

  func test_insert_atInvalidIndex_ignored() {
      let list = LinkedList<Int>()
      list.append(1)
      list.insert(2, at: 5)
      list.insert(3, at: -1)

      XCTAssertEqual(list.count, 1)
  }

  func test_removeHead_returnsValue() {
      let list = LinkedList<Int>()
      list.append(1)
      list.append(2)

      let removed = list.removeHead()

      XCTAssertEqual(removed, 1)
      XCTAssertEqual(list.head, 2)
      XCTAssertEqual(list.count, 1)
  }

  func test_removeHead_emptyList_returnsNil() {
      let list = LinkedList<Int>()
      XCTAssertNil(list.removeHead())
  }

  func test_remove_atIndex() {
      let list = LinkedList<Int>()
      list.append(1)
      list.append(2)
      list.append(3)

      let removed = list.remove(at: 1)

      XCTAssertEqual(removed, 2)
      XCTAssertEqual(list.value(at: 0), 1)
      XCTAssertEqual(list.value(at: 1), 3)
      XCTAssertEqual(list.count, 2)
  }

  func test_remove_lastElement_updatesTail() {
      let list = LinkedList<Int>()
      list.append(1)
      list.append(2)

      _ = list.remove(at: 1)

      XCTAssertEqual(list.tail, 1)
      XCTAssertEqual(list.head, 1)
  }

  func test_removeAll_clearsEverything() {
      let list = LinkedList<Int>()
      list.append(1)
      list.append(2)
      list.removeAll()

      XCTAssertTrue(list.isEmpty)
      XCTAssertEqual(list.count, 0)
      XCTAssertNil(list.head)
      XCTAssertNil(list.tail)
  }

  func test_value_atIndex() {
      let list = LinkedList<String>()
      list.append("a")
      list.append("b")
      list.append("c")

      XCTAssertEqual(list.value(at: 0), "a")
      XCTAssertEqual(list.value(at: 1), "b")
      XCTAssertEqual(list.value(at: 2), "c")
      XCTAssertNil(list.value(at: 3))
      XCTAssertNil(list.value(at: -1))
  }

  func test_description_format() {
      let list = LinkedList<Int>()
      list.append(1)
      list.append(2)
      list.append(3)

      XCTAssertEqual(list.description, "[1 -> 2 -> 3]")
  }

  func test_description_empty() {
      let list = LinkedList<Int>()
      XCTAssertEqual(list.description, "[]")
  }
}

// MARK: - Queue Tests

final class QueueTests: XCTestCase {

  func test_enqueue_dequeue_fifo() {
      let queue = Queue<Int>()
      queue.enqueue(1)
      queue.enqueue(2)
      queue.enqueue(3)

      XCTAssertEqual(queue.dequeue(), 1)
      XCTAssertEqual(queue.dequeue(), 2)
      XCTAssertEqual(queue.dequeue(), 3)
      XCTAssertNil(queue.dequeue())
  }

  func test_front_back() {
      let queue = Queue<Int>()
      queue.enqueue(1)
      queue.enqueue(2)

      XCTAssertEqual(queue.front, 1)
      XCTAssertEqual(queue.back, 2)
  }

  func test_empty_queue() {
      let queue = Queue<Int>()

      XCTAssertNil(queue.front)
      XCTAssertNil(queue.back)
      XCTAssertTrue(queue.isEmpty)
  }
}

// MARK: - ThreadSafeLinkedList Tests

final class ThreadSafeLinkedListTests: XCTestCase {

  func test_concurrent_append_integrity() {
      let list = ThreadSafeLinkedList<Int>()
      let iterations = 1000
      let threads = 10
      let expectation = expectation(description: "all done")
      expectation.expectedFulfillmentCount = threads

      for t in 0..<threads {
          DispatchQueue.global().async {
              for i in 0..<iterations {
                  list.append(t * iterations + i)
              }
              expectation.fulfill()
          }
      }

      wait(for: [expectation], timeout: 10.0)
      XCTAssertEqual(list.count, threads * iterations)
  }

  func test_concurrent_read_write() {
      let list = ThreadSafeLinkedList<Int>()
      for i in 0..<100 {
          list.append(i)
      }

      let expectation = expectation(description: "all done")
      expectation.expectedFulfillmentCount = 20

      // 10 readers
      for _ in 0..<10 {
          DispatchQueue.global().async {
              for i in 0..<100 {
                  _ = list.value(at: i % list.count)
              }
              expectation.fulfill()
          }
      }

      // 10 writers
      for _ in 0..<10 {
          DispatchQueue.global().async {
              for i in 0..<10 {
                  list.append(i)
              }
              expectation.fulfill()
          }
      }

      wait(for: [expectation], timeout: 10.0)
      XCTAssertEqual(list.count, 200) // 100 + 10*10
  }
}

// MARK: - ThreadSafeQueue Tests

final class ThreadSafeQueueTests: XCTestCase {

  func test_concurrent_enqueue_dequeue() {
      let queue = ThreadSafeQueue<Int>()
      let enqueueCount = 1000
      let expectation = expectation(description: "all done")
      expectation.expectedFulfillmentCount = 2

      var dequeued: [Int] = []
      let lock = NSLock()

      // Producer
      DispatchQueue.global().async {
          for i in 0..<enqueueCount {
              queue.enqueue(i)
          }
          expectation.fulfill()
      }

      // Consumer
      DispatchQueue.global().async {
          var count = 0
          while count < enqueueCount {
              if let value = queue.dequeue() {
                  lock.lock()
                  dequeued.append(value)
                  lock.unlock()
                  count += 1
              } else {
                  Thread.sleep(forTimeInterval: 0.001)
              }
          }
          expectation.fulfill()
      }

      wait(for: [expectation], timeout: 10.0)
      XCTAssertEqual(dequeued.count, enqueueCount)
  }

  func test_front_back_threadSafe() {
      let queue = ThreadSafeQueue<Int>()
      queue.enqueue(1)
      queue.enqueue(2)

      let expectation = expectation(description: "reads done")
      expectation.expectedFulfillmentCount = 100

      for _ in 0..<100 {
          DispatchQueue.global().async {
              _ = queue.front
              _ = queue.back
              expectation.fulfill()
          }
      }

      wait(for: [expectation], timeout: 5.0)
  }
}
