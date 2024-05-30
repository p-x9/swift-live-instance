import Foundation
import LiveInstanceC

public func liveInstances<T: AnyObject>(for `class`: T.Type) -> WeakHashTable<T> {
    let table = WeakHashTable<T>()

    /* Get All Zones */
    let reader: @convention(c) (task_t, vm_address_t, vm_size_t, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> kern_return_t = { _, remoteAddress, _, localMemory in
        localMemory?.pointee = .init(bitPattern: remoteAddress)
        return KERN_SUCCESS
    }
    var zonesBaseAddress: UnsafeMutablePointer<vm_address_t>?
    var zonesCount: UInt32 = 0
    malloc_get_all_zones(TASK_NULL, reader, &zonesBaseAddress, &zonesCount)

    guard let zonesBaseAddress else { return table }


    /* Iterate zones */
    let zonesBuffer = UnsafeBufferPointer(start: zonesBaseAddress, count: Int(zonesCount))
    let zones = Array(zonesBuffer)

    for zoneAddress in zones {
        guard let zonePointer = UnsafeMutablePointer<malloc_zone_t>(bitPattern: zoneAddress) else {
            continue
        }
        let zone = zonePointer.pointee

        guard let introspect = zone.introspect?.pointee else { continue }

        guard let lock = introspect.force_lock,
              let unlock = introspect.force_unlock,
              let enumerator = introspect.enumerator else {
            continue
        }

        let callback = Callback(
            class: `class`,
            callback: { object in
                unlock(zonePointer)
                defer { lock(zonePointer) }
                table.add(object as? T)
            }
        )

        lock(zonePointer)
        let result = enumerator(
            TASK_NULL,
            unsafeBitCast(callback, to: UnsafeMutableRawPointer.self),
            numericCast(MALLOC_PTR_IN_USE_RANGE_TYPE),
            zoneAddress,
            reader,
            rangeCallback
        )
        unlock(zonePointer)

        print(result == KERN_SUCCESS)
    }

    return table
}


var rangeCallback: @convention(c) (task_t, UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<vm_range_t>?, UInt32) -> Void = { _, context, _, rangeBaseAddress, rangeCount in
    guard let context,
          let rangeBaseAddress else {
        return
    }

    let callback = unsafeBitCast(context, to: Callback.self)

    let ranges = UnsafeBufferPointer(start: rangeBaseAddress, count: Int(rangeCount))
    for range in ranges {
        guard let ptr = UnsafeRawPointer(bitPattern: range.address) else { continue }
        var classAddress = ptr.load(as: uintptr_t.self)

#if arch(arm64)
        if (classAddress & 1) != 0 { classAddress &= objc_debug_isa_class_mask() }
#endif

        guard RegisteredClass.ptrs.contains(classAddress),
              let clsPtr = UnsafeRawPointer(bitPattern: classAddress) else {
            continue
        }
        let cls: AnyClass = unsafeBitCast(clsPtr, to: AnyClass.self)

        if validate(ptr),
           malloc_size(ptr) >= class_getInstanceSize(cls),
           uintptr_t(bitPattern: callback.class) == classAddress || isSubClass(cls, of: callback.targetClass) {
            let unmanaged = Unmanaged<AnyObject>.fromOpaque(ptr)
            callback.callback(unmanaged.takeUnretainedValue())
        }
    }
}

// ref: https://blog.timac.org/2016/1124-testing-if-an-arbitrary-pointer-is-a-valid-objective-c-object/
func validate(_ ptr: UnsafeRawPointer) -> Bool {
    let pointer = uintptr_t(bitPattern: ptr)

    if _objc_isTaggedPointer(ptr) {
        return true
    }

    if pointer % numericCast(MemoryLayout<uintptr_t>.size) != 0 {
        return false
    }

    // https://github.com/llvm/llvm-project/blob/b5db2e196928bfbaf5b4e3af50dc60caae498f30/lldb/examples/summaries/cocoa/objc_runtime.py#L40C5-L48C51
    if (pointer & 0xFFFF800000000000) != 0 {
        return false
    }
    return true
}

func isSubClass(_ target: AnyClass, of superClass: AnyClass) -> Bool {
    if let target = target as? NSObject.Type,
       let superClass = superClass as? NSObject.Type {
        return target.isSubclass(of: superClass)
    }

    var current: AnyClass? = target
    while true {
        guard let _current = current else { break }
        if _current == superClass {
            return true
        }
        current = class_getSuperclass(_current)
    }
    return false
}

