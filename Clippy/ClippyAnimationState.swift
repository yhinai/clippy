import Foundation

/// Represents the different animation states for the Clippy character
enum ClippyAnimationState {
    case idle      // User pressed Option+X, waiting for input
    case writing   // User is typing text
    case thinking  // AI is processing the query (minimum 3 seconds)
    case done      // AI has completed processing
    
    /// The GIF file name for this animation state
    var gifFileName: String {
        switch self {
        case .idle:
            return "clippy-idle"
        case .writing:
            return "clippy-writing"
        case .thinking:
            return "clippy-thinking"
        case .done:
            return "clippy-done"
        }
    }
    
    /// Default message to display for this state
    var defaultMessage: String {
        switch self {
        case .idle:
            return "Listening..."
        case .writing:
            return "Got it..."
        case .thinking:
            return "Thinking..."
        case .done:
            return "Done!"
        }
    }
}
