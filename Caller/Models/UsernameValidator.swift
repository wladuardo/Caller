import Foundation

enum UsernameValidator {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validate(_ value: String) -> String? {
        let username = normalized(value)

        guard !username.isEmpty else {
            return "Введите никнейм."
        }

        guard username.count >= 3 else {
            return "Никнейм должен содержать минимум 3 символа."
        }

        guard username.count <= 20 else {
            return "Никнейм не должен быть длиннее 20 символов."
        }

        let pattern = "^[A-Za-z0-9]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        guard predicate.evaluate(with: username) else {
            return "Используйте только английские буквы и цифры."
        }

        return nil
    }
}
