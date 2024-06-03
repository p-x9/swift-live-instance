import Foundation
import LiveInstanceC

public func liveInstances<T: AnyObject>(of `class`: T.Type) -> WeakHashTable<T> {
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
              isReadablePointer(unsafeBitCast(lock, to: UnsafeRawPointer.self)),
              isReadablePointer(unsafeBitCast(unlock, to: UnsafeRawPointer.self)),
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
        let _ = enumerator(
            TASK_NULL,
            unsafeBitCast(callback, to: UnsafeMutableRawPointer.self),
            numericCast(MALLOC_PTR_IN_USE_RANGE_TYPE),
            zoneAddress,
            reader,
            rangeCallback
        )
        unlock(zonePointer)

//        debugPrint(result == KERN_SUCCESS)
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
           uintptr_t(bitPattern: callback.class) == classAddress || isSubClass(cls, of: callback.targetClass),
           malloc_size(ptr) >= class_getInstanceSize(cls) {
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

    if !isReadablePointer(ptr) {
        return false
    }

    if _objc_cls(ptr) == 0 {
        return false
    }

    return true
}

// ref: https://github.com/FLEXTool/FLEX/blob/1b983160cc188aff18284c1d990121cdb1e42e9c/Classes/Utility/Runtime/Objc/FLEXObjcInternal.mm#L78
// ref: https://blog.timac.org/2016/1124-testing-if-an-arbitrary-pointer-is-a-valid-objective-c-object/
func isReadablePointer(_ ptr: UnsafeRawPointer) -> Bool {
    var address: vm_address_t
    var vmsize: vm_size_t = 0
    var info = vm_region_basic_info_64()

    let VM_REGION_BASIC_INFO_COUNT_64 = MemoryLayout<vm_region_basic_info_64>.size / MemoryLayout<UInt32>.size
    var infoCount = mach_msg_type_number_t(VM_REGION_BASIC_INFO_COUNT_64)
    var object: memory_object_name_t = 0

#if _ptrauth(_arm64e)
    address = vm_address_t(UInt(bitPattern: __ptrauth_strip_function_pointer(ptr)))
#else
    address = vm_address_t(UInt(bitPattern: ptr))
#endif

    let error = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: Int32.self, capacity: Int(infoCount)) {
            vm_region_64(
                mach_task_self_,
                &address,
                &vmsize,
                VM_REGION_BASIC_INFO_64,
                $0,
                &infoCount,
                &object
            )
        }
    }

    if error != KERN_SUCCESS || (info.protection & VM_PROT_READ) == 0 {
        return false
    }

#if _ptrauth(_arm64e)
    address = vm_address_t(UInt(bitPattern: __ptrauth_strip_function_pointer(ptr)))
#else
    address = vm_address_t(UInt(bitPattern: ptr))
#endif

    let buf = [UInt8](repeating: 0, count: MemoryLayout<vm_address_t>.size)
    var size = vm_size_t(0)

    let readError = vm_read_overwrite(
        mach_task_self_,
        address,
        vm_size_t(buf.count),
        buf.withUnsafeBufferPointer { vm_address_t(bitPattern: $0.baseAddress!) },
        &size
    )

    if readError != KERN_SUCCESS {
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

        // check if super class is readable
        let new = _objc_super(_current)
        guard new != 0,
              let ptr = UnsafeRawPointer(bitPattern: new),
              isReadablePointer(ptr) else {
            break
        }
        current = unsafeBitCast(ptr, to: AnyClass.self)
    }
    return false
}

