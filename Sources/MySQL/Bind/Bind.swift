import Core
import JSON
import Foundation
import CMySQL

/**
    This structure is used both for statement input (data values sent to the server)
    and output (result values returned from the server):

    The Swift version consists of a wrapper around MySQL's implementation
    to ensure proper freeing of allocated memory.
*/
public final class Bind {
    public typealias CBind = MYSQL_BIND
    
    /// UTF-8 stores characters using 1-4 bytes, represented in Swift as unsigned integers.
    typealias Char = UInt8
    
    /**
     The raw C binding.
     */
    public let cBind: CBind
    
    /**
        Creates a binding from a raw C binding.
    */
    public init(cBind: CBind) {
        self.cBind = cBind
    }
    
    /**
        Creates a NULL input binding.
    */
    public init() {
        var cBind = CBind()
        cBind.buffer_type = MYSQL_TYPE_NULL
        
        self.cBind = cBind
    }
    
    /**
        Creates an output binding from an expected Field.
    */
    public init(_ field: Field) {
        var cBind = CBind()
        
        cBind.buffer_type = field.cField.type
        let length: Int

        // FIXME: Find better way to get length

        switch field.cField.type {
            case MYSQL_TYPE_DATE,
                 MYSQL_TYPE_DATETIME,
                 MYSQL_TYPE_TIMESTAMP,
                 MYSQL_TYPE_TIME:
            length = MemoryLayout<MYSQL_TIME>.size
        default:
            length = Int(field.cField.max_length)
        }

        cBind.buffer_length = UInt(length)
        cBind.buffer = UnsafeMutableRawPointer.allocate(bytes: length, alignedTo: MemoryLayout<Void>.alignment)
        
        
        cBind.length = UnsafeMutablePointer<UInt>.allocate(capacity: 1)
        cBind.is_null = UnsafeMutablePointer<my_bool>.allocate(capacity: 1)
        cBind.error = UnsafeMutablePointer<my_bool>.allocate(capacity: 1)
        
        self.cBind = cBind
    }
    
    /**
        Creates an input binding from a String.
    */
    public convenience init(_ string: String) {
        let bytes = Array(string.utf8)
        let buffer = UnsafeMutablePointer<Char>.allocate(capacity: bytes.count)
        for (i, byte) in bytes.enumerated() {
            buffer[i] = Char(byte)
        }
        
        self.init(type: MYSQL_TYPE_STRING, buffer: buffer, bufferLength: bytes.count)
    }
    
    /**
        Creates an input binding from an Int.
    */
    public convenience init(_ int: Int) {
        let buffer = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        buffer.initialize(to: Int64(int))
        
        self.init(type: MYSQL_TYPE_LONGLONG, buffer: buffer, bufferLength: MemoryLayout<Int64>.size)
    }
    
    /**
        Creates an input binding from a UInt.
    */
    public convenience init(_ int: UInt) {
        let buffer = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
        buffer.initialize(to: UInt64(int))
        
        self.init(type: MYSQL_TYPE_LONGLONG, buffer: buffer, bufferLength: MemoryLayout<UInt64>.size)
    }
    
    /**
        Creates an input binding from an Double.
    */
    public convenience init(_ int: Double) {
        let buffer = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        buffer.initialize(to: Double(int))
        
        self.init(type: MYSQL_TYPE_DOUBLE, buffer: buffer, bufferLength: MemoryLayout<Double>.size)
    }

    /**
        Creates an input binding from an array of bytes.
    */
    public convenience init(_ bytes: Bytes) {
        let pointer = UnsafeMutablePointer<Byte>.allocate(capacity: bytes.count)
        for (i, byte) in bytes.enumerated() {
            pointer[i] = byte
        }
        self.init(type: MYSQL_TYPE_STRING, buffer: pointer, bufferLength: bytes.count)
    }

    /**
         Creates an input binding from a Date

         https://dev.mysql.com/doc/refman/5.7/en/c-api-prepared-statement-date-handling.html
    */
    public convenience init(_ date: Date) {
        let time = date.makeTime()
        let pointer = UnsafeMutablePointer<MYSQL_TIME>.allocate(capacity: MemoryLayout<MYSQL_TIME>.size)
        pointer.initialize(to: time)
        self.init(type: MYSQL_TYPE_DATETIME, buffer: pointer, bufferLength: MemoryLayout<MYSQL_TIME>.size)
    }

    /**
        Creates an input binding from a field variant,
        input buffer, and input buffer length.
    */
    public init<T>(type: Field.Variant, buffer: UnsafeMutablePointer<T>, bufferLength: Int, unsigned: Bool = false) {
        var cBind = CBind()
        
        cBind.buffer = UnsafeMutableRawPointer(buffer)
        cBind.buffer_length = UInt(bufferLength)
        
        cBind.length = UnsafeMutablePointer<UInt>.allocate(capacity: 1)
        cBind.length.initialize(to: cBind.buffer_length)
        
        
        cBind.buffer_type = type
        
        if unsigned {
            cBind.is_unsigned = 1
        } else {
            cBind.is_unsigned = 0
        }
        
        self.cBind = cBind
    }
    
    /**
        Buffer type variant.
    */
    public var variant: Field.Variant {
        return cBind.buffer_type
    }
    
    /**
        Frees allocated memory from the underlying
        C binding.
    */
    deinit {
        if let pointer = cBind.buffer {
            let bufferLength = Int(cBind.buffer_length)
            pointer.deallocate(bytes: bufferLength, alignedTo: MemoryLayout<Void>.alignment)
        }

        if let pointer = cBind.length {
            pointer.deinitialize()
            pointer.deallocate(capacity: 1)
        }

        if let pointer = cBind.is_null {
            pointer.deinitialize()
            pointer.deallocate(capacity: 1)
        }

        if let pointer = cBind.error {
            pointer.deinitialize()
            pointer.deallocate(capacity: 1)
        }
    }
}

extension Node {
    /**
        Creates in input binding from a MySQL Value.
    */
    var bind: Bind {
        switch wrapped {
        case .number(let number):
            switch number {
            case .int(let int):
                return Bind(int)
            case .double(let double):
                return Bind(double)
            case .uint(let uint):
                return Bind(uint)
            }
        case .string(let string):
            return Bind(string)
        case .null:
            return Bind()
        case .array(let array):
            var bytes: Bytes = []
            do {
                bytes = try JSON(node: array).makeBytes()
            } catch {
                print("[MySQL] Could not convert array to JSON.")
            }
            return Bind(bytes)
        case .bytes(let bytes):
            return Bind(bytes)
        case .object(let object):
            var bytes: Bytes = []
            do {
                bytes = try JSON(node: object).makeBytes()
            } catch {
                print("[MySQL] Could not convert object to JSON.")
            }
            return Bind(bytes)
        case .bool(let bool):
            return Bind(bool ? 1 : 0)
        case .date(let date):
            return Bind(date)
        }
    }
}

extension Calendar {
    static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        if let utc = TimeZone.utc {
            cal.timeZone = utc
        }
        return cal
    }()
}

extension TimeZone {
    static let utc = TimeZone(secondsFromGMT: 0)
}

extension Date {
    func makeTime() -> MYSQL_TIME {
        var time = MYSQL_TIME()

        let comps = makeComponents()
        time.year = comps.year.flatMap { UInt32($0) } ?? 0
        time.month = comps.month.flatMap { UInt32($0) } ?? 0
        time.day = comps.day.flatMap { UInt32($0) } ?? 0
        time.hour = comps.hour.flatMap { UInt32($0) } ?? 0
        time.minute = comps.minute.flatMap { UInt32($0) } ?? 0
        time.second = comps.second.flatMap { UInt32($0) } ?? 0

        return time
    }

    private func makeComponents() -> DateComponents {
        return Calendar.gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second], from: self)
    }
}
