//
//  File.swift
//  Caller
//
//  Created by Владислав Ковальский on 10.04.2026.
//

import SwiftUI

extension View {
    @inlinable
    func onFirstAppear(perform action: (() -> Void)? = nil) -> some View {
        modifier(ViewOnFirstAppearModifier(perform: action))
    }
}

@usableFromInline
struct ViewOnFirstAppearModifier: ViewModifier {
    @State
    private var didFirstAppear: Bool = false
    private let action: (() -> Void)?
    
    @usableFromInline
    init(perform action: (() -> Void)? = nil) {
        self.action = action
    }
    
    @usableFromInline
    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !didFirstAppear else { return }
                
                didFirstAppear = true
                action?()
            }
    }
}
