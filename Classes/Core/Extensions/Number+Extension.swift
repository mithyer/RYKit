//
//  Bundle.swift
//  Pods
//
//  Created by ray on 2025/2/14.
//

extension Numeric {
    public var nilIfZero: Self? {
        self == 0 ? nil : self
    }
}

extension FixedWidthInteger {

    /// Safely creates an integer from a floating-point value.
    ///
    /// - Parameters:
    ///   - float: The floating-point value to convert.
    ///   - strict: When `false`, fractional values are truncated using Swift's default integer conversion behavior.
    ///             When `true`, only finite values without a fractional component are accepted.
    /// - Returns: `nil` if the value is not finite or cannot be represented by this integer type.
    init?<T>(safe float: T, strict: Bool = false) where T: BinaryFloatingPoint {
        guard float.isFinite else {
            return nil
        }

        if strict, float.rounded(.towardZero) != float {
            return nil
        }

        let value = Double(float)
        guard value >= Double(Self.min), value <= Double(Self.max) else {
            return nil
        }

        self.init(value)
    }
}
