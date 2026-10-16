import Foundation

// The bundled static SDK contains Swift code. Keep this pod a mixed-language
// target so Xcode includes Swift runtime and compatibility libraries at link time.
internal enum SwiftRuntimeSupport {}
