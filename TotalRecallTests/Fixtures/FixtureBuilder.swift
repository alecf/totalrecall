import Foundation
@testable import TotalRecallCore

/// Builds synthetic test fixtures with realistic but entirely fake process data.
/// NEVER uses real captured data (command-line args on real systems contain secrets).
enum FixtureBuilder {
    static let now = Date()

    // MARK: - Chrome Processes

    static func chromeMain() -> ProcessSnapshot {
        makeSnapshot(
            pid: 1000, name: "Google Chrome",
            path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            args: ["Google Chrome", "--enable-features=SomeFeature"],
            bundleId: "com.google.Chrome",
            footprint: 200 * mb, resident: 180 * mb, shared: 50 * mb
        )
    }

    static func chromeRenderer(pid: Int32 = 1001, profile: String = "Default", footprint: UInt64 = 150 * mb) -> ProcessSnapshot {
        makeSnapshot(
            pid: pid, name: "Google Chrome Helper (Renderer)",
            path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/Current/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
            args: ["Google Chrome Helper (Renderer)", "--type=renderer", "--profile-directory=\(profile)"],
            parentPid: 1000, responsiblePid: 1000,
            footprint: footprint, resident: footprint - 20 * mb, shared: 30 * mb
        )
    }

    static func chromeGPU() -> ProcessSnapshot {
        makeSnapshot(
            pid: 1010, name: "Google Chrome Helper (GPU)",
            path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/Current/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)",
            args: ["Google Chrome Helper (GPU)", "--type=gpu-process"],
            parentPid: 1000, responsiblePid: 1000,
            footprint: 90 * mb, resident: 80 * mb, shared: 40 * mb
        )
    }

    // MARK: - Electron App (VS Code)

    static func vscodeMain() -> ProcessSnapshot {
        makeSnapshot(
            pid: 2000, name: "Electron",
            path: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron",
            args: ["Electron"],
            bundleId: "com.microsoft.VSCode",
            footprint: 300 * mb, resident: 250 * mb, shared: 60 * mb
        )
    }

    static func vscodeRenderer(pid: Int32 = 2001) -> ProcessSnapshot {
        makeSnapshot(
            pid: pid, name: "Electron Helper (Renderer)",
            path: "/Applications/Visual Studio Code.app/Contents/Frameworks/Electron Framework.framework/Versions/Current/Helpers/Electron Helper (Renderer).app/Contents/MacOS/Electron Helper (Renderer)",
            args: ["Electron Helper (Renderer)", "--type=renderer"],
            parentPid: 2000, responsiblePid: 2000,
            footprint: 200 * mb, resident: 180 * mb, shared: 45 * mb
        )
    }

    // MARK: - System Services

    static func windowServer() -> ProcessSnapshot {
        makeSnapshot(
            pid: 150, name: "WindowServer",
            path: "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer",
            footprint: 500 * mb, resident: 480 * mb, shared: 100 * mb
        )
    }

    static func mdsStores() -> ProcessSnapshot {
        makeSnapshot(
            pid: 200, name: "mds_stores",
            path: "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Versions/A/Support/mds_stores",
            footprint: 120 * mb, resident: 100 * mb, shared: 20 * mb
        )
    }

    static func kernelTask() -> ProcessSnapshot {
        makeSnapshot(
            pid: 0, name: "kernel_task",
            path: "",
            footprint: 2 * gb, resident: 2 * gb, shared: 0
        )
    }

    // MARK: - Node.js Framework Processes

    /// Next.js dev server tree: npm → node next dev → next-server
    static func nextjsDevServer(rootPid: Int32 = 4000) -> [ProcessSnapshot] {
        let npmPid = rootPid
        let nodePid = rootPid + 1
        let serverPid = rootPid + 2
        return [
            makeSnapshot(
                pid: npmPid, name: "node",
                path: "/usr/local/bin/node",
                args: ["npm", "run", "dev"],
                parentPid: 1,
                footprint: 23 * mb, resident: 20 * mb, shared: 5 * mb
            ),
            makeSnapshot(
                pid: nodePid, name: "node",
                path: "/usr/local/bin/node",
                args: ["node", "/project/node_modules/.bin/next", "dev", "-p", "3000"],
                parentPid: npmPid,
                footprint: 68 * mb, resident: 60 * mb, shared: 10 * mb
            ),
            makeSnapshot(
                pid: serverPid, name: "next-server",
                path: "/usr/local/bin/node",
                args: ["next-server", "(v15.5.14)"],
                parentPid: nodePid,
                footprint: 524 * mb, resident: 480 * mb, shared: 20 * mb
            ),
        ]
    }

    /// NestJS dev server tree: npm → node nest start → node main
    static func nestjsDevServer(rootPid: Int32 = 4100) -> [ProcessSnapshot] {
        let npmPid = rootPid
        let nestPid = rootPid + 1
        let mainPid = rootPid + 2
        return [
            makeSnapshot(
                pid: npmPid, name: "node",
                path: "/usr/local/bin/node",
                args: ["npm", "run", "dev:api"],
                parentPid: 1,
                footprint: 21 * mb, resident: 18 * mb, shared: 5 * mb
            ),
            makeSnapshot(
                pid: nestPid, name: "node",
                path: "/usr/local/bin/node",
                args: ["node", "/project/apps/api/node_modules/.bin/nest", "start", "--watch"],
                parentPid: npmPid,
                footprint: 1024 * mb, resident: 900 * mb, shared: 30 * mb
            ),
            makeSnapshot(
                pid: mainPid, name: "node",
                path: "/usr/local/bin/node",
                args: ["node", "--enable-source-maps", "/project/apps/api/dist/main"],
                parentPid: nestPid,
                footprint: 182 * mb, resident: 160 * mb, shared: 15 * mb
            ),
        ]
    }

    /// NestJS via turbo: npm → turbo → npm → nest start → node main
    static func nestjsViaTurbo(rootPid: Int32 = 4200) -> [ProcessSnapshot] {
        let npmPid = rootPid
        let turboPid = rootPid + 1
        let npm2Pid = rootPid + 2
        let nestPid = rootPid + 3
        let mainPid = rootPid + 4
        return [
            makeSnapshot(
                pid: npmPid, name: "node",
                path: "/usr/local/bin/node",
                args: ["node", "/project/node_modules/.bin/turbo", "dev"],
                parentPid: 1,
                footprint: 12 * mb, resident: 10 * mb, shared: 3 * mb
            ),
            makeSnapshot(
                pid: turboPid, name: "turbo",
                path: "/project/node_modules/turbo-darwin-arm64/bin/turbo",
                args: ["turbo", "dev", "--filter=@myapp/api"],
                parentPid: npmPid,
                footprint: 31 * mb, resident: 28 * mb, shared: 5 * mb
            ),
            makeSnapshot(
                pid: npm2Pid, name: "node",
                path: "/usr/local/bin/node",
                args: ["npm", "run", "dev"],
                parentPid: turboPid,
                footprint: 22 * mb, resident: 19 * mb, shared: 5 * mb
            ),
            makeSnapshot(
                pid: nestPid, name: "node",
                path: "/usr/local/bin/node",
                args: ["node", "/project/apps/api/node_modules/.bin/nest", "start", "--watch"],
                parentPid: npm2Pid,
                footprint: 1024 * mb, resident: 900 * mb, shared: 30 * mb
            ),
            makeSnapshot(
                pid: mainPid, name: "node",
                path: "/usr/local/bin/node",
                args: ["node", "--enable-source-maps", "/project/apps/api/dist/main"],
                parentPid: nestPid,
                footprint: 182 * mb, resident: 160 * mb, shared: 15 * mb
            ),
        ]
    }

    // MARK: - Generic Processes

    static func genericProcess(pid: Int32, name: String, path: String = "", footprint: UInt64 = 50 * mb) -> ProcessSnapshot {
        makeSnapshot(pid: pid, name: name, path: path, footprint: footprint, resident: footprint - 5 * mb, shared: 10 * mb)
    }

    // MARK: - Full Fixture Set

    static func devWorkstation() -> [ProcessSnapshot] {
        [
            // Chrome with 2 profiles
            chromeMain(),
            chromeGPU(),
            chromeRenderer(pid: 1001, profile: "Default", footprint: 150 * mb),
            chromeRenderer(pid: 1002, profile: "Default", footprint: 120 * mb),
            chromeRenderer(pid: 1003, profile: "Default", footprint: 80 * mb),
            chromeRenderer(pid: 1004, profile: "Profile 1", footprint: 200 * mb),
            chromeRenderer(pid: 1005, profile: "Profile 1", footprint: 100 * mb),

            // VS Code (Electron)
            vscodeMain(),
            vscodeRenderer(pid: 2001),
            vscodeRenderer(pid: 2002),

            // System
            kernelTask(),
            windowServer(),
            mdsStores(),

            // Generic
            genericProcess(pid: 3000, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari", footprint: 400 * mb),
            genericProcess(pid: 3001, name: "Mail", path: "/Applications/Mail.app/Contents/MacOS/Mail", footprint: 150 * mb),
        ]
    }

    // MARK: - Helpers

    private static let mb: UInt64 = 1024 * 1024
    private static let gb: UInt64 = 1024 * 1024 * 1024

    private static func makeSnapshot(
        pid: Int32,
        name: String,
        path: String,
        args: [String] = [],
        parentPid: Int32 = 1,
        responsiblePid: Int32 = 0,
        bundleId: String? = nil,
        footprint: UInt64,
        resident: UInt64,
        shared: UInt64
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid,
            name: name,
            path: path,
            commandLineArgs: args,
            parentPid: parentPid,
            responsiblePid: responsiblePid == 0 ? pid : responsiblePid,
            bundleIdentifier: bundleId,
            workingDirectory: nil,
            physFootprint: footprint,
            residentSize: resident,
            sharedMemory: shared,
            startTimeSec: UInt64(now.timeIntervalSince1970),
            startTimeUsec: 0,
            firstSeen: now,
            lastSeen: now,
            exitedAt: nil,
            isPartialData: false
        )
    }
}
