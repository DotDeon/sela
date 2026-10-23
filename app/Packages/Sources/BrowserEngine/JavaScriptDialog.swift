public enum JavaScriptDialog: Equatable, Sendable {
    case alert(message: String)
    case confirm(message: String)
    case prompt(message: String, defaultText: String?)
}

public enum JavaScriptDialogResult: Equatable, Sendable {
    /// OK. For a prompt, `text` is what the user typed.
    case accepted(text: String?)
    /// Cancel, or the dialog went away without an answer.
    case dismissed
}
