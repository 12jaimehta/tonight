import Foundation

/// Who is asking to change a task. The child path cannot turn typing on.
public enum TaskEditor: Equatable, Sendable {
    case parent
    case child
}

public enum TypingAccess {
    /// Typing is per task, and only a parent who has just passed the gate may turn it on.
    public static func canEnable(editor: TaskEditor, gateUnlocked: Bool) -> Bool {
        editor == .parent && gateUnlocked
    }
}
