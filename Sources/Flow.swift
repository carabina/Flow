/**
 *  Flow - Operation Oriented Programming in Swift
 *
 *  For usage, see documentation of the classes/symbols listed in this file, as well
 *  as the guide available at: github.com/johnsundell/flow
 *
 *  Copyright (c) 2015 John Sundell. Licensed under the MIT license, as follows:
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in all
 *  copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 *  SOFTWARE.
 */

import Foundation

// MARK: - API

/**
 *  Protocol used to define a Flow operation
 *
 *  An operation performs a task, that can be either asynchronous or asynchronous,
 *  and calls a completion handler once it has finished.
 */
public protocol FlowOperation {
    /// Perform the operation with a completion handler
    func performWithCompletionHandler(completionHandler: () -> Void)
}

/// Extension adding convenience APIs to objects conforming to `FlowOperation`
public extension FlowOperation {
    /// Perform the operation without a completion handler
    func perform() {
        self.performWithCompletionHandler({})
    }
}

/**
 *  Protocol used to define a collection of Flow operations
 *
 *  A collection forms a group out of a number of operations, that can either be
 *  exceuted in parallel or in sequence. Common for all collections is that their
 *  initializer and that they can be mutated by adding new operations.
 */
public protocol FlowOperationCollection {
    /// Initialize an instance with operations to form the collection with
    init(operations: [FlowOperation])
    /// Add an operation to the collection
    mutating func addOperation(operation: FlowOperation)
}

/// Extension adding convenience APIs to objects conforming to `FlowOperationCollection`
public extension FlowOperationCollection {
    /// Initialize an instance with a single operation to form the collection with
    init(operation: FlowOperation) {
        self.init(operations: [operation])
    }
    
    /// Add a series of operations to the collection
    mutating func addOperations(operations: [FlowOperation]) {
        for operation in operations {
            self.addOperation(operation)
        }
    }
}

/**
 *  Flow operation that executes a synchronous closure
 *
 *  Once the operation's closure has finished executing, the operation is considered
 *  finished. See `FlowAsyncClosureOperation` for its asynchronous counterpart.
 */
public class FlowClosureOperation: FlowOperation {
    private let closure: () -> Void
    
    /// Initialize an instance with a closure that the operation should perform
    public init(closure: () -> Void) {
        self.closure = closure
    }
    
    public func performWithCompletionHandler(completionHandler: () -> Void) {
        self.closure()
        completionHandler()
    }
}

/**
 *  Flow operation that executes a closure & waits for a completion handler to be called
 *
 *  This operation is consindered finished when the closure that makes up this operation
 *  calls its completion handler. Please note that it's up to the user of this class to
 *  chose to perform any work asynchronously, it's not a guarantee that the operation
 *  itself makes.
 *
 *  See `FlowClosureOperation` for its synchronous counterpart.
 */
public class FlowAsyncClosureOperation: FlowOperation {
    private let closure: (() -> Void) -> Void
    
    /// Initialize an instance with a closure that the operation should perform
    public init(closure: (() -> Void) -> Void) {
        self.closure = closure
    }
    
    public func performWithCompletionHandler(completionHandler: () -> Void) {
        self.closure(completionHandler)
    }
}

/**
 *  Flow operation that waits for an amount of time, then executes its completion handler
 *
 *  This operation doesn't do anything in of itself, but is very useful when creating
 *  operation sequences (see `FlowOperationSequence` for more information), as it enables
 *  certain operations to be delayed within a sequence.
 */
public class FlowDelayOperation: FlowOperation {
    private let delay: NSTimeInterval
    
    /// Initialize an instance with a delay in seconds
    public init(delay: NSTimeInterval) {
        self.delay = delay
    }
    
    public func performWithCompletionHandler(completionHandler: () -> Void) {
        let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(self.delay * Double(NSEC_PER_SEC)))
        dispatch_after(delayTime, dispatch_get_main_queue(), completionHandler)
    }
}

/**
 *  Flow operation collection that executes its member operations in sequence
 *
 *  Once performed, this operation will start executing its member operations, one by one
 *  until all of them have finished. Once all have finished, the sequence's own completion
 *  handler is called.
 *
 *  The collection is copied once it starts performing, so any further mutations won't be
 *  reflected in the instance that is currently performing.
 */
public struct FlowOperationSequence: FlowOperation, FlowOperationCollection {
    private var operations: [FlowOperation]
    
    public init(operations: [FlowOperation] = []) {
        self.operations = operations
    }
    
    public mutating func addOperation(operation: FlowOperation) {
        self.operations.append(operation)
    }
    
    public func performWithCompletionHandler(completionHandler: () -> Void) {
        FlowOperationSequencePerformer(operationSequence: self).performWithCompletionHandler(completionHandler)
    }
}

/**
 *  Flow operation collection that executes all of its member operations at once
 *
 *  Once performed, this operation will execute all of its member operations at once, and
 *  call its own completion handler once all of them have finished. The operations are
 *  started in the same order as they are added.
 *
 *  The collection is copied once it starts performing, so any further mutations won't be
 *  reflected in the instance that is currently performing.
 */
public struct FlowOperationGroup: FlowOperation, FlowOperationCollection {
    private var operations: [FlowOperation]
    
    public init(operations: [FlowOperation] = []) {
        self.operations = operations
    }
    
    public mutating func addOperation(operation: FlowOperation) {
        self.operations.append(operation)
    }
    
    public func performWithCompletionHandler(completionHandler: () -> Void) {
        FlowOperationGroupPerformer(operationGroup: self).performWithCompletionHandler(completionHandler)
    }
}

/// Observation protocol for FlowOperationQueue
public protocol FlowOperationQueueObserver: class {
    /// Sent to an operation queue's observers when it's about to start performing an operation
    func operationQueue(queue: FlowOperationQueue, willStartPerformingOperation operation: FlowOperation)
    /// Sent to an operation queue's observers when it became empty
    func operationQueueDidBecomeEmpty(queue: FlowOperationQueue)
}

/// Extension containing default implementations for FlowOperationQueueObserver's methods
public extension FlowOperationQueueObserver {
    func operationQueue(queue: FlowOperationQueue, willStartPerformingOperation operation: FlowOperation) {}
    func operationQueueDidBecomeEmpty(queue: FlowOperationQueue) {}
}

/**
 *  Flow operation collection that enqueues operations and executes them once idle
 *
 *  This collection cannot be performed, rather it auto-performs any added operations once
 *  any currently performed operation has finished, or immediately if it's idle.
 *
 *  You can also add observers to the operation queue, to get notified when the queue
 *  becomes empty; see `FlowOperationQueueObserver` for more information.
 */
public final class FlowOperationQueue: FlowOperationCollection {
    private var operations: [FlowOperation]
    private var isPerformingOperation: Bool
    private var observers: [ObjectIdentifier : FlowOperationQueueObserverWrapper]
    
    public init(operations: [FlowOperation] = []) {
        self.operations = operations
        self.isPerformingOperation = false
        self.observers = [:]
        self.performFirstOperation()
    }
    
    public func addOperation(operation: FlowOperation) {
        self.operations.append(operation)
        self.performFirstOperation()
    }
    
    /// Add an operation to the queue, with a completion handler that gets called once it has finished
    public func addOperation(operation: FlowOperation, completionHandler: () -> Void) {
        let wrapper = FlowAsyncClosureOperation(closure: {
            let internalCompletionHandler = $0
            
            operation.performWithCompletionHandler({
                internalCompletionHandler()
                completionHandler()
            })
        })
        self.operations.append(wrapper)
    }
    
    public func addObserver(observer: FlowOperationQueueObserver) {
        let identifier = ObjectIdentifier(observer)
        
        if self.observers[identifier] != nil {
            return
        }
        
        let wrapper = FlowOperationQueueObserverWrapper(observer: observer, queue: self)
        self.observers[identifier] = wrapper
    }
    
    public func removeObserver(observer: FlowOperationQueueObserver) {
        let identifier = ObjectIdentifier(observer)
        self.observers[identifier] = nil
    }
    
    private func performFirstOperation() {
        if self.isPerformingOperation  {
            return
        }
        
        if self.operations.count == 0 {
            for observerWrapper in self.observers.values {
                observerWrapper.observer?.operationQueueDidBecomeEmpty(self)
            }
            
            return
        }
        
        self.isPerformingOperation = true
        
        let operation = self.operations.removeFirst()
        
        for observerWrapper in self.observers.values {
            observerWrapper.observer?.operationQueue(self, willStartPerformingOperation: operation)
        }
        
        operation.performWithCompletionHandler({
            self.isPerformingOperation = false
            self.performFirstOperation()
        })
    }
}

/**
 *  Repeater that can be used to repeat a Flow operation
 *
 *  A repeater takes an operation (or an array of operations) and keeps repeating it until
 *  stopped. This is useful for implementing repeating animations, or tasks that should be
 *  performed on a regular basis.
 *
 *  To make a repeater start repeating, call `start()`.
 */
public class FlowOperationRepeater {
    /// Whether the repeater is currently stopped
    public private(set) var isStopped: Bool
    
    private let operation: FlowOperation
    
    /// Initialize an instance with an operation to repeat, and optionally an interval between repeats
    public init(operation: FlowOperation, interval: NSTimeInterval = 0) {
        if interval > 0 {
            let delayOperation = FlowDelayOperation(delay: interval)
            self.operation = FlowOperationSequence(operations: [operation, delayOperation])
        } else {
            self.operation = operation
        }
        
        self.isStopped = true
    }
    
    /// Initialize an instance with an array of operations, and optionally an interval between repeats.
    /// The interval will be added at the end of the sequence formed from the array of operations.
    public convenience init(operations: [FlowOperation], interval: NSTimeInterval = 0) {
        self.init(operation: FlowOperationSequence(operations: operations), interval: interval)
    }
    
    /// Start repeating the repeater's operation
    public func start() {
        if !self.isStopped {
            return
        }
        
        self.isStopped = false
        self.performOperation()
    }
    
    /// Stop repeating. The repeater will continue performing any current operation until finished.
    public func stop() {
        self.isStopped = true
    }
    
    private func performOperation() {
        if self.isStopped {
            return
        }
        
        self.operation.performWithCompletionHandler(self.performOperation)
    }
}

// MARK: - Private

private class FlowOperationSequencePerformer: FlowOperation {
    private var operationSequence: FlowOperationSequence
    
    init(operationSequence: FlowOperationSequence) {
        self.operationSequence = operationSequence
    }
    
    func performWithCompletionHandler(completionHandler: () -> Void) {
        if self.operationSequence.operations.isEmpty {
            return completionHandler()
        }
        
        self.operationSequence.operations.removeFirst().performWithCompletionHandler({
            self.performWithCompletionHandler(completionHandler)
        })
    }
}

private class FlowOperationGroupPerformer: FlowOperation {
    private var operationGroup: FlowOperationGroup
    
    init(operationGroup: FlowOperationGroup) {
        self.operationGroup = operationGroup
    }
    
    func performWithCompletionHandler(completionHandler: () -> Void) {
        if self.operationGroup.operations.isEmpty {
            return completionHandler()
        }
        
        var operationsLeft = self.operationGroup.operations.count
        
        for operation in self.operationGroup.operations {
            operation.performWithCompletionHandler({
                operationsLeft -= 1
                
                if operationsLeft == 0 {
                    completionHandler()
                }
            })
        }
    }
}

private class FlowOperationQueueObserverWrapper {
    weak var observer: FlowOperationQueueObserver? {
        willSet {
            if let observer = self.observer where newValue == nil {
                self.queue?.removeObserver(observer)
            }
        }
    }
    weak var queue: FlowOperationQueue?
    
    init(observer: FlowOperationQueueObserver, queue: FlowOperationQueue) {
        self.observer = observer
        self.queue = queue
    }
}
