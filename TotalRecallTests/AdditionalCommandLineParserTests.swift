import Testing
@testable import TotalRecallCore

@Suite("CommandLineParser - additional coverage")
struct AdditionalCommandLineParserTests {

    // MARK: - electronProcessType additional cases

    @Test("Extracts --type=utility")
    func extractsUtilityProcessType() {
        #expect(CommandLineParser.electronProcessType(from: ["Helper", "--type=utility"]) == .utility)
    }

    @Test("Extracts --type=broker")
    func extractsBrokerProcessType() {
        #expect(CommandLineParser.electronProcessType(from: ["Helper", "--type=broker"]) == .broker)
    }

    @Test("Extracts --type=zygote")
    func extractsZygoteProcessType() {
        #expect(CommandLineParser.electronProcessType(from: ["Helper", "--type=zygote"]) == .zygote)
    }

    @Test("Extracts --type=crashpad-handler")
    func extractsCrashpadProcessType() {
        #expect(CommandLineParser.electronProcessType(from: ["Helper", "--type=crashpad-handler"]) == .crashpad)
    }

    // MARK: - resolveShimDisplayName additional cases

    @Test("Resolves bun shim running a known tool")
    func resolvesBunShimWithKnownTool() {
        // bun is in the ["node", "npx", "bun"] group → resolves runtime tool
        let result = CommandLineParser.resolveShimDisplayName(args: ["bun", "/project/node_modules/.bin/jest"])
        #expect(result == "bun (Jest)")
    }

    @Test("Resolves bun shim with unknown script falls back to filename")
    func resolvesBunShimWithUnknownScript() {
        let result = CommandLineParser.resolveShimDisplayName(args: ["bun", "/project/scripts/custom.js"])
        #expect(result == "bun (custom.js)")
    }

    @Test("Resolves yarn shim with subcommand")
    func resolvesYarnShimSubcommand() {
        let result = CommandLineParser.resolveShimDisplayName(args: ["yarn", "run", "dev"])
        #expect(result == "yarn run dev")
    }

    @Test("Resolves pnpm shim with subcommand")
    func resolvesPnpmShimSubcommand() {
        let result = CommandLineParser.resolveShimDisplayName(args: ["pnpm", "run", "build"])
        #expect(result == "pnpm run build")
    }

    @Test("Resolves npx shim running MCP server")
    func resolvesNpxShimMCPServer() {
        let result = CommandLineParser.resolveShimDisplayName(
            args: ["npx", "@modelcontextprotocol/server-filesystem"]
        )
        // npx is in ["node", "npx", "bun"] group → resolves runtime
        #expect(result == "npx (MCP Server: Filesystem)")
    }

    @Test("Resolves shim from path-based first arg")
    func resolvesShimFromPathBasedFirstArg() {
        // args[0] is a path — uses executableName to extract the tool name
        let result = CommandLineParser.resolveShimDisplayName(args: ["/usr/local/bin/npm", "start"])
        #expect(result == "npm start")
    }

    @Test("Returns nil for args with only volta-shim as tool name")
    func returnsNilForVoltaShimToolName() {
        // toolName ends up as "volta-shim" → explicitly excluded
        let result = CommandLineParser.resolveShimDisplayName(args: ["/path/to/volta-shim"])
        #expect(result == nil)
    }

    // MARK: - resolveRuntimeTool additional tool signals

    @Test("Identifies Vite by path component")
    func identifiesVite() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/.bin/vite"]) == "Vite")
    }

    @Test("Identifies Webpack by path component")
    func identifiesWebpack() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/.bin/webpack"]) == "Webpack")
    }

    @Test("Identifies TypeScript Server by tsserver component")
    func identifiesTypeScriptServer() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/typescript/bin/tsserver"]) == "TypeScript Server")
    }

    @Test("Identifies Language Server by typescript-language-server component")
    func identifiesLanguageServer() {
        #expect(CommandLineParser.resolveRuntimeTool(args: [
            "node", "/project/node_modules/.bin/typescript-language-server", "--stdio",
        ]) == "Language Server")
    }

    @Test("Identifies Prettier by path component")
    func identifiesPrettier() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/.bin/prettier"]) == "Prettier")
    }

    @Test("Identifies Tailwind CSS by tailwindcss component")
    func identifiesTailwindCSS() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/.bin/tailwindcss"]) == "Tailwind CSS")
    }

    @Test("Identifies Copilot by path component")
    func identifiesCopilot() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/.bin/copilot"]) == "Copilot")
    }

    @Test("Identifies Playwright by path component")
    func identifiesPlaywright() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/.bin/playwright"]) == "Playwright")
    }

    @Test("Identifies Jupyter by path component")
    func identifiesJupyter() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "/project/node_modules/.bin/jupyter"]) == "Jupyter")
    }

    @Test("Skips leading flags before finding the script")
    func skipsLeadingFlags() {
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "--experimental-vm-modules", "/project/node_modules/.bin/jest"]) == "Jest")
    }

    @Test("Returns nil when only flags are present (no script)")
    func returnsNilForFlagsOnly() {
        // All args after args[0] are flags → no script name found
        #expect(CommandLineParser.resolveRuntimeTool(args: ["node", "--inspect", "--experimental-vm-modules"]) == nil)
    }

    // MARK: - mcpServerName additional patterns

    @Test("Resolves mcp-server- prefixed package")
    func resolvesMcpServerPrefixedPackage() {
        #expect(CommandLineParser.mcpServerName(from: [
            "npx", "mcp-server-postgres",
        ]) == "Postgres")
    }

    @Test("Resolves @playwright/mcp pattern")
    func resolvesPlaywrightMCPPattern() {
        #expect(CommandLineParser.mcpServerName(from: [
            "npx", "@playwright/mcp",
        ]) == "Playwright")
    }

    @Test("Resolves mcp- prefixed package")
    func resolvesMcpPrefixedPackage() {
        #expect(CommandLineParser.mcpServerName(from: [
            "npx", "mcp-brave",
        ]) == "Brave")
    }

    @Test("Humanizes GitLab server name with correct casing")
    func humanizesGitLabName() {
        #expect(CommandLineParser.mcpServerName(from: [
            "npx", "@modelcontextprotocol/server-gitlab",
        ]) == "GitLab")
    }

    @Test("Humanizes Sentry server name with correct casing")
    func humanizesSentryName() {
        #expect(CommandLineParser.mcpServerName(from: [
            "npx", "@modelcontextprotocol/server-sentry",
        ]) == "Sentry")
    }

    @Test("Returns nil for mcpServerName with single-element args")
    func mcpServerNameNilForSingleArg() {
        #expect(CommandLineParser.mcpServerName(from: ["node"]) == nil)
    }

    @Test("Skips flag args when looking for MCP server name")
    func mcpServerNameSkipsFlags() {
        #expect(CommandLineParser.mcpServerName(from: [
            "npx", "-y", "@modelcontextprotocol/server-github",
        ]) == "GitHub")
    }

    // MARK: - pathComponentNames edge cases

    @Test("pathComponentNames returns empty set for empty string")
    func pathComponentNamesEmptyString() {
        let components = CommandLineParser.pathComponentNames(from: "")
        #expect(components.isEmpty)
    }

    @Test("pathComponentNames handles whitespace-only string")
    func pathComponentNamesWhitespaceOnly() {
        let components = CommandLineParser.pathComponentNames(from: "   ")
        #expect(components.isEmpty)
    }

    @Test("pathComponentNames extracts stem from .js file")
    func pathComponentNamesExtractsStemFromJS() {
        let components = CommandLineParser.pathComponentNames(from: "/project/build.js")
        #expect(components.contains("build.js"))
        #expect(components.contains("build"))
    }

    @Test("pathComponentNames handles versioned npm packages via @ separator")
    func pathComponentNamesVersionedPackage() {
        let components = CommandLineParser.pathComponentNames(from: "@scope/package@1.2.3")
        // stripPackageVersion should strip @1.2.3, keeping @scope/package
        #expect(components.contains("@scope/package") || components.contains("package"))
    }

    @Test("pathComponentNames with backslash-style Windows paths")
    func pathComponentNamesBackslashPaths() {
        let components = CommandLineParser.pathComponentNames(from: "project\\node_modules\\.bin\\jest")
        #expect(components.contains("jest"))
    }

    // MARK: - stripPackageVersion via mcpServerName

    @Test("Resolves versioned scoped MCP package correctly")
    func resolvesMCPWithVersionedScopedPackage() {
        // @modelcontextprotocol/server-filesystem@1.0.0 → strip version → server-filesystem
        #expect(CommandLineParser.mcpServerName(from: [
            "npx", "@modelcontextprotocol/server-filesystem@1.0.0",
        ]) == "Filesystem")
    }
}
