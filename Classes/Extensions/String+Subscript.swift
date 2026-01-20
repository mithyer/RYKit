//
//  String+IntSub.swift
//  RYKit
//
//  Created by mao rui on 2026/1/20.
//

extension String {

    public subscript(_ range: Range<Int>) -> Substring {
        let lower = max(0, range.lowerBound)
        let upper = min(self.count, range.upperBound)

        guard lower < upper else { return "" }

        let startIndex = self.index(self.startIndex, offsetBy: lower)
        let endIndex = self.index(self.startIndex, offsetBy: upper)
        
        return self[startIndex..<endIndex]
    }

    public subscript(_ range: ClosedRange<Int>) -> Substring {
        let lower = max(0, range.lowerBound)
        let upper = min(self.count - 1, range.upperBound)

        guard lower <= upper else { return "" }

        let startIndex = self.index(self.startIndex, offsetBy: lower)
        let endIndex = self.index(self.startIndex, offsetBy: upper)

        return self[startIndex...endIndex]
    }
    
    public subscript(_ range: Range<Int>) -> String {
        let sub: Substring = self[range]
        return String(sub)
    }

    public subscript(_ range: ClosedRange<Int>) -> String {
        let sub: Substring = self[range]
        return String(sub)
    }
}
