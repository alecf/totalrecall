import Foundation

/// Masks secrets in command-line arguments at capture time.
/// Applied before storage, display, or serialization.
enum RedactionFilter {
    private static let secretFlags: Set<String> = [
        "-p", "--password", "--token", "--secret", "--key",
        "--auth", "--api-key", "--db-password", "--access-token",
        "--client-secret", "--private-key", "--passphrase",
    ]

    private static let envPrefixes = ["-e", "--env"]

    /// Redact a list of command-line arguments, masking values after known secret flags.
    static func redact(_ args: [String]) -> [String] {
        var result: [String] = []
        var redactNext = false

        for arg in args {
            if redactNext {
                result.append("[REDACTED]")
                redactNext = false
                continue
            }

            // Check flag=value patterns (--password=secret)
            if let eqIndex = arg.firstIndex(of: "=") {
                let flag = String(arg[arg.startIndex..<eqIndex]).lowercased()
                if secretFlags.contains(flag) || isSecretEnvVar(flag: flag, arg: arg) {
                    result.append(flag + "=[REDACTED]")
                    continue
                }
            }

            // Check if this flag means the next arg is a secret
            let lower = arg.lowercased()
            if secretFlags.contains(lower) {
                result.append(arg)
                redactNext = true
                continue
            }

            // Check -e KEY=VALUE / --env KEY=VALUE
            if envPrefixes.contains(lower) {
                result.append(arg)
                redactNext = true  // Next arg is KEY=VALUE, redact the value
                continue
            }

            // Check Authorization headers: -H "Authorization: Bearer ..."
            if lower == "-h" {
                result.append(arg)
                redactNext = true  // Conservatively redact header values
                continue
            }

            // Check for long base64-like strings (potential tokens/keys)
            if looksLikeSecret(arg) {
                result.append("[REDACTED]")
                continue
            }

            result.append(arg)
        }

        return result
    }

    private static func isSecretEnvVar(flag: String, arg: String) -> Bool {
        let upper = arg.uppercased()
        let secretEnvPatterns = [
            "SECRET", "TOKEN", "PASSWORD", "KEY", "AUTH", "CREDENTIAL",
            "AWS_SECRET", "API_KEY", "PRIVATE_KEY",
        ]
        return secretEnvPatterns.contains(where: { upper.contains($0) }) &&
               arg.contains("=")
    }

    /// Heuristic: long alphanumeric/base64 strings (>40 chars) that look like tokens.
    private static func looksLikeSecret(_ arg: String) -> Bool {
        guard arg.count > 40 else { return false }
        // Must be mostly alphanumeric + base64 chars
        let base64Chars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+/=_-"))
        let nonBase64 = arg.unicodeScalars.filter { !base64Chars.contains($0) }
        return nonBase64.count < arg.count / 10  // >90% base64 chars
    }
}
