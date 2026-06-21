import Testing
@testable import TotalRecallCore

@Suite("RedactionFilter - additional edge cases")
struct AdditionalRedactionFilterTests {

    // MARK: - args[0] is never redacted

    @Test("args[0] executable path is never redacted even if it looks like a token")
    func args0ExecutableNeverRedacted() {
        // A long base64-like string in args[0] (executable path) must NOT be redacted
        let longBase64Path = "/" + String(repeating: "abcdefghABCDEFGH12345678", count: 4)  // 97+ chars
        let args = [longBase64Path, "--normal-flag"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted[0] == longBase64Path)
    }

    @Test("single-element args list is returned unchanged")
    func singleArgNotRedacted() {
        let args = ["/usr/bin/node"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == args)
    }

    @Test("empty args list is returned unchanged")
    func emptyArgsReturnedUnchanged() {
        let redacted = RedactionFilter.redact([])
        #expect(redacted == [])
    }

    // MARK: - Flag=value patterns

    @Test("masks --api-key= inline flag value")
    func apiKeyInlineMasked() {
        let args = ["app", "--api-key=sk-1234567890abcdef"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["app", "--api-key=[REDACTED]"])
    }

    @Test("masks --secret= inline flag value")
    func secretInlineMasked() {
        let args = ["app", "--secret=mysupersecret"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["app", "--secret=[REDACTED]"])
    }

    @Test("masks --key= inline flag value")
    func keyInlineMasked() {
        let args = ["app", "--key=keyvalue123"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["app", "--key=[REDACTED]"])
    }

    @Test("masks --access-token= inline flag value")
    func accessTokenInlineMasked() {
        let args = ["app", "--access-token=mytoken"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["app", "--access-token=[REDACTED]"])
    }

    @Test("masks --client-secret= inline flag value")
    func clientSecretInlineMasked() {
        let args = ["oauth", "--client-secret=abc123def456"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["oauth", "--client-secret=[REDACTED]"])
    }

    @Test("masks --private-key= inline flag value")
    func privateKeyInlineMasked() {
        let args = ["ssh", "--private-key=BEGINRSAPRIVATE"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["ssh", "--private-key=[REDACTED]"])
    }

    @Test("masks --db-password= inline flag value")
    func dbPasswordInlineMasked() {
        let args = ["app", "--db-password=hunter2"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["app", "--db-password=[REDACTED]"])
    }

    // MARK: - Next-arg patterns

    @Test("masks --token next argument")
    func tokenNextArgMasked() {
        let args = ["app", "--token", "my-secret-token"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["app", "--token", "[REDACTED]"])
    }

    @Test("masks --auth next argument")
    func authNextArgMasked() {
        let args = ["app", "--auth", "Bearer mytoken"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["app", "--auth", "[REDACTED]"])
    }

    @Test("masks --passphrase next argument")
    func passphraseNextArgMasked() {
        let args = ["gpg", "--passphrase", "my-passphrase-value"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["gpg", "--passphrase", "[REDACTED]"])
    }

    @Test("masks --private-key next argument")
    func privateKeyNextArgMasked() {
        let args = ["tool", "--private-key", "/path/to/key"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["tool", "--private-key", "[REDACTED]"])
    }

    @Test("masks --access-token next argument")
    func accessTokenNextArgMasked() {
        let args = ["cli", "--access-token", "ghp_secretvalue"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["cli", "--access-token", "[REDACTED]"])
    }

    // MARK: - Env prefix patterns

    @Test("masks value after -e flag")
    func eFlagMasksNextArg() {
        let args = ["docker", "run", "-e", "MY_API_KEY=secret"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted[3] == "[REDACTED]")
    }

    @Test("masks value after --env flag")
    func envFlagMasksNextArg() {
        let args = ["docker", "--env", "DATABASE_PASSWORD=db123"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["docker", "--env", "[REDACTED]"])
    }

    // MARK: - -H header pattern

    @Test("masks value after -H flag for header redaction")
    func hFlagMasksNextArg() {
        let args = ["curl", "-H", "X-Custom-Header: value"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["curl", "-H", "[REDACTED]"])
    }

    // MARK: - looksLikeSecret boundary

    @Test("does not redact strings at exactly 40 characters")
    func exactly40CharsNotRedacted() {
        let str40 = String(repeating: "a", count: 40)  // Exactly 40 = not > 40 → not redacted
        let args = ["app", str40]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted[1] == str40)
    }

    @Test("redacts strings longer than 40 alphanumeric characters")
    func over40AlphanumericCharsRedacted() {
        let str41 = String(repeating: "abcDEF123", count: 5)  // 45 chars, all alphanumeric
        let args = ["app", str41]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted[1] == "[REDACTED]")
    }

    @Test("does not redact long strings with many non-base64 characters (e.g. paths)")
    func longPathWithSlashesNotRedacted() {
        // > 40 chars but has lots of '/' which are not in base64 charset
        let longPath = "/this/is/a/very/long/path/that/has/many/slash/chars/and/goes/on/and/on"
        let args = ["app", longPath]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted[1] == longPath)
    }

    // MARK: - Multiple flags in sequence

    @Test("correctly handles multiple secret flags in sequence")
    func multipleSecretFlagsInSequence() {
        let args = ["app", "--token", "tok1", "--verbose", "--password", "pass1", "--output", "file.txt"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted == ["app", "--token", "[REDACTED]", "--verbose", "--password", "[REDACTED]", "--output", "file.txt"])
    }

    @Test("redactNext resets correctly after each secret value")
    func redactNextResetsAfterValue() {
        // After --token val, the next non-secret arg should NOT be redacted
        let args = ["app", "--token", "secret", "not-a-secret"]
        let redacted = RedactionFilter.redact(args)
        #expect(redacted[3] == "not-a-secret")
    }

    // MARK: - isSecretEnvVar path

    @Test("masks env-var style args containing SECRET pattern")
    func secretEnvVarStyleArg() {
        // An arg like "MY_SECRET_KEY=value" containing a secret keyword with '='
        let args = ["env", "MY_SECRET_KEY=hunter2"]
        let redacted = RedactionFilter.redact(args)
        // isSecretEnvVar fires because arg has '=' and contains 'SECRET'
        // The flag (before '=') is 'my_secret_key' which isn't in secretFlags
        // so isSecretEnvVar is called and should match
        #expect(redacted[1].contains("[REDACTED]"))
    }
}
