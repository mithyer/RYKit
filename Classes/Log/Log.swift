//
//  Log.swift
//  RYKit
//
//  Created by ray on 2025/12/9.
//

enum LogType: String {
    case eventCenter
}

fileprivate func log(_ str: @autoclosure () -> String, type: LogType) {
    #if DEBUG
    let str = str()
    print(str)
    LogRecorder.shared.saveLog(content: str, key: type.rawValue)
    #endif
}

func log_event_center(_ str: String) {
    log(str, type: .eventCenter)
}
