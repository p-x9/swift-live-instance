//
//  WeakHashTable.swift
//
//
//  Created by p-x9 on 2023/03/10.
//

import Foundation

/// A class for holding multiple objects with weak references.
///
/// Holds multiple objects by weak reference.
/// Internally, NSHashTable is used.
public class WeakHashTable<T: AnyObject> {

    /// List of objects held with weak reference
    public var objects: [T] {
        accessQueue.sync { _objects.allObjects }
    }

    private var _objects: NSHashTable<T> = NSHashTable.weakObjects()
    private let accessQueue: DispatchQueue = .init(
        label:"com.github.p-x9.liveInstance.WeakHashTable.\(T.self)",
        attributes: .concurrent
    )

    /// Default initializer
    public init() {}


    /// Initialize with initial value of object list
    /// - Parameter objects: initial value of object list
    public init(_ objects: [T]) {
        for object in objects {
            _objects.add(object)
        }
    }

    /// Add a object to be held with weak reference
    /// - Parameter object: Objects to be added
    public func add(_ object: T?) {
        accessQueue.sync(flags: .barrier) {
            _objects.add(object)
        }
    }

    /// Remove a object to be held with weak reference
    /// - Parameter object: Objects to be deleted.
    public func remove(_ object: T?) {
        accessQueue.sync(flags: .barrier) {
            _objects.remove(object)
        }
    }
}


extension WeakHashTable : Sequence {
    public typealias Iterator = Array<T>.Iterator

    public func makeIterator() -> Iterator {
        return objects.makeIterator()
    }
}
