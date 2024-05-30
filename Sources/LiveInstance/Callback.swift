//
//  Callback.swift
//
//
//  Created by p-x9 on 2024/05/31
//  
//

import Foundation

class Callback {
    let `class`: UnsafeRawPointer
    let callback: @convention(block) (AnyObject) -> Void

    let targetClass: AnyClass

    init<T: AnyObject>(`class`: T.Type, callback: @escaping (AnyObject) -> Void) {
        self.class = unsafeBitCast(`class` as Any.Type, to: UnsafeRawPointer.self)
        self.targetClass = `class`
        self.callback = callback
    }
}
