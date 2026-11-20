//
//  A1DebugLog.swift
//  A1AppSDK
//
//  Console output for SDK diagnostics: printed in Debug builds only and compiled out of
//  Release, so production apps stay quiet and the message is never even built.
//

import Foundation

func sdkDebugPrint(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
