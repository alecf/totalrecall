import Testing
@testable import TotalRecallCore

@Suite("Command Line Parser")
struct CommandLineParserTests {
    // MARK: - electronProcessType

    @Test("Extracts the --type= flag")
    func extractsProcessType() {
        #expect(CommandLineParser.electronProcessType(from: ["Helper", "--type=renderer"]) == .renderer)
        #expect(CommandLineParser.electronProcessType(from: ["Helper", "--type=gpu-process"]) == .gpu)
    }

    @Test("Returns nil for unknown or missing --type=")
    func returnsNilForUnknownType() {
        #expect(CommandLineParser.electronProcessType(from: ["Helper", "--type=bogus"]) == nil)
        #expect(CommandLineParser.electronProcessType(from: ["Helper"]) == nil)
    }

    // MARK: - chromeProfileDirectory

    @Test("Extracts the --profile-directory= flag")
    func extractsProfileDirectory() {
        #expect(CommandLineParser.chromeProfileDirectory(from: ["Helper", "--profile-directory=Profile 1"]) == "Profile 1")
    }

    @Test("Returns nil when no profile directory flag is present")
    func returnsNilWithoutProfileDirectory() {
        #expect(CommandLineParser.chromeProfileDirectory(from: ["Helper"]) == nil)
    }

    // MARK: - pathContainsFramework

    @Test("Detects framework and app bundle paths")
    func detectsFrameworkPaths() {
        #expect(CommandLineParser.pathContainsFramework(
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helper",
            named: "Google Chrome Framework"
        ))
        #expect(CommandLineParser.pathContainsFramework("/Applications/Foo.app/Contents/MacOS/Foo", named: "Foo"))
        #expect(!CommandLineParser.pathContainsFramework("/Applications/Bar.app/Contents/MacOS/Bar", named: "Foo"))
    }

    // MARK: - appNameFromPath

    @Test("Extracts the app name from a bundle path")
    func extractsAppName() {
        #expect(CommandLineParser.appNameFromPath("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") == "Google Chrome")
    }

    @Test("Returns nil when the path has no .app component")
    func returnsNilWithoutAppComponent() {
        #expect(CommandLineParser.appNameFromPath("/usr/local/bin/node") == nil)
    }

    // MARK: - executableName

    @Test("Returns the last path component as the executable name")
    func extractsExecutableName() {
        #expect(CommandLineParser.executableName(from: "/usr/local/bin/node") == "node")
        #expect(CommandLineParser.executableName(from: "node") == "node")
    }

    // MARK: - isVersionString

    @Test("Recognizes dotted numeric version strings")
    func recognizesVersionStrings() {
        #expect(CommandLineParser.isVersionString("22.21.0"))
        #expect(CommandLineParser.isVersionString("1.0"))
    }

    @Test("Rejects non-version strings")
    func rejectsNonVersionStrings() {
        #expect(!CommandLineParser.isVersionString("node"))
        #expect(!CommandLineParser.isVersionString("22"))
        #expect(!CommandLineParser.isVersionString("v22.21.0"))
    }

    // MARK: - isVoltaPath / resolveVoltaShim

    @Test("Recognizes volta-managed paths")
    func recognizesVoltaPaths() {
        #expect(CommandLineParser.isVoltaPath("/Users/alecf/.volta/tools/image/node/22.21.0/bin/node"))
        #expect(!CommandLineParser.isVoltaPath("/usr/local/bin/node"))
    }

    @Test("Resolves the real tool name from a version-string process via args[0]")
    func resolvesVoltaShimFromArgs() {
        let resolved = CommandLineParser.resolveVoltaShim(
            processName: "22.21.0",
            path: "/Users/alecf/.volta/tools/image/node/22.21.0/bin/node",
            args: ["node", "/project/server.js"]
        )
        #expect(resolved == "node")
    }

    @Test("Resolves the tool name from a volta path when the process name isn't a version string")
    func resolvesVoltaShimFromPath() {
        let resolved = CommandLineParser.resolveVoltaShim(
            processName: "node",
            path: "/Users/alecf/.volta/tools/image/node/22.21.0/bin/node",
            args: []
        )
        #expect(resolved == "node")
    }

    @Test("Returns nil for non-volta processes with non-version names")
    func returnsNilForNonVoltaProcesses() {
        let resolved = CommandLineParser.resolveVoltaShim(
            processName: "node",
            path: "/usr/local/bin/node",
            args: []
        )
        #expect(resolved == nil)
    }

    // MARK: - isShimProcess

    @Test("Recognizes volta, mise, and asdf shims")
    func recognizesShimProcesses() {
        #expect(CommandLineParser.isShimProcess("volta-shim", path: "/Users/alecf/.volta/bin/node"))
        #expect(CommandLineParser.isShimProcess("node", path: "/Users/alecf/.local/share/mise/shims/node"))
        #expect(CommandLineParser.isShimProcess("node", path: "/Users/alecf/.asdf/shims/node"))
        #expect(!CommandLineParser.isShimProcess("node", path: "/usr/local/bin/node"))
    }

    // MARK: - resolveShimDisplayName

    @Test("Shows npm subcommands for npm/yarn/pnpm shims")
    func resolvesNpmShimDisplayName() {
        #expect(CommandLineParser.resolveShimDisplayName(args: ["npm", "run", "dev:api"]) == "npm run dev:api")
    }

    @Test("Resolves runtime detail for node shims")
    func resolvesNodeShimDisplayName() {
        #expect(CommandLineParser.resolveShimDisplayName(args: ["node", "/project/node_modules/.bin/vite"]) == "node (Vite)")
    }

    @Test("Returns nil for empty args or bare volta-shim")
    func resolvesShimDisplayNameEdgeCases() {
        #expect(CommandLineParser.resolveShimDisplayName(args: []) == nil)
        #expect(CommandLineParser.resolveShimDisplayName(args: ["volta-shim"]) == nil)
    }

    // MARK: - resolveRuntimeTool

    @Test("Identifies known runtime tools by exact path component")
    func identifiesKnownRuntimeTools() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/.bin/jest"]) == "Jest")
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/.bin/eslint"]) == "ESLint")
    }

    @Test("Falls back to the script filename when no known tool matches")
    func fallsBackToScriptName() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/scripts/build.js"]) == "build.js")
    }

    @Test("Returns nil for args with no script")
    func resolveRuntimeToolReturnsNilForNoScript() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node"]) == nil)
    }

    // MARK: - mcpServerName

    @Test("Resolves @modelcontextprotocol/server-* package names")
    func resolvesModelContextProtocolServerName() {
        #expect(CommandLineParser.mcpServerName(from: ["npx", "@modelcontextprotocol/server-filesystem"]) == "Filesystem")
        #expect(CommandLineParser.mcpServerName(from: [
            "node", "/project/node_modules/@modelcontextprotocol/server-github/dist/index.js",
        ]) == "GitHub")
    }

    @Test("Returns nil when args contain no MCP server reference")
    func mcpServerNameReturnsNilWhenAbsent() {
        #expect(CommandLineParser.mcpServerName(from: ["node", "/project/server.js"]) == nil)
        #expect(CommandLineParser.mcpServerName(from: ["node"]) == nil)
    }
}
