//
//  Store.swift
//  Caller
//
//  Created by Владислав Ковальский on 10.04.2026.
//

import SwiftUI

protocol Store<State, Input>: AnyObject, Observable {
    associatedtype State
    associatedtype Input: Sendable
    
    var state: State { get set }
    
    func trigger(_ input: Input) async
}

extension Store {
    @MainActor
    func update(_ closure: @MainActor (inout State) -> Void) {
        closure(&state)
    }
}
