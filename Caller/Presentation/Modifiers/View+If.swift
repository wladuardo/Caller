//
//  View+If.swift
//  Caller
//
//  Created by Владислав Ковальский on 21.04.2026.
//

import SwiftUI

public extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
