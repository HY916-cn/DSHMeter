import SwiftUI

// Select the native property wrapper explicitly when Command Line Tools lack
// the SwiftUIMacros plugin introduced with the macOS 27 SDK.
typealias ViewState<Value> = SwiftUI.State<Value>
