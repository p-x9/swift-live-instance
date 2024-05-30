//
//  RegisteredClass.swift
//
//
//  Created by p-x9 on 2024/05/31
//  
//

import Foundation

enum RegisteredClass {
    static var classes: [AnyClass] = {
        fetchRegisteredClasses()
    }()

    static var ptrs: Set<uintptr_t> = {
        Set(
            fetchRegisteredClasses().map {
                unsafeBitCast($0, to: uintptr_t.self)
            }
        )
    }()

    static func update() {
        classes = fetchRegisteredClasses()
        ptrs = Set(
            fetchRegisteredClasses().map {
                unsafeBitCast($0, to: uintptr_t.self)
            }
        )
    }
}

extension RegisteredClass {
    static func fetchRegisteredClasses() -> [AnyClass] {
        var count: UInt32 = 0
        guard let _classes = objc_copyClassList(&count) else { return [] }
        var classes: [AnyClass] = []
        for cls in UnsafeBufferPointer(start: _classes, count: Int(count)) {
            classes.append(cls)
        }
        free(UnsafeMutableRawPointer(_classes))
        return classes
    }
}
