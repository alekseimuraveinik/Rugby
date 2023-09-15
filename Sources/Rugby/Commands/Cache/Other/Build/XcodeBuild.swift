//
//  XcodeBuild.swift
//  Rugby
//
//  Created by Vyacheslav Khorkov on 31.01.2021.
//  Copyright © 2021 Vyacheslav Khorkov. All rights reserved.
//

import Files

struct XcodeBuild {
    let project: String
    let scheme: String
    let sdk: SDK
    let arch: String?
    let config: String?
    let xcargs: [String]

    func build() throws {
        let currentFolder = Folder.current.path.shellFriendly
        var arguments = [
            "-project \(project)",
            "-scheme \(scheme)",
            "-sdk \(sdk.xcodebuild)",
            "SYMROOT=\(currentFolder)\(String.buildFolder)"
        ]
        arguments.append(contentsOf: xcargs)

        if var arch = arch {
			if arch == "auto" {
				arch = sdk.defaultARCH
			}
            switch sdk {
            case .sim:
                arguments.append("ARCHS=\"\(ARCH.x86_64) \(ARCH.arm64)\"")
            case .ios:
                arguments.append("ARCHS=\(arch)")
            }
        }
        if let config = config {
            arguments.append("-config \(config.shellFriendly)")
        }
        arguments.append("| tee " + .rawBuildLog)

        try XcodeBuildRunner(rawLogPath: .rawBuildLog, logPath: .buildLog).run(
            "NSUnbufferedIO=YES xcodebuild",
            args: arguments
        )
    }
}

struct XcodeFrameworkReleaseBuild {
    let targets: Set<String>

    func build() throws {
        for target in targets {
            try buildFramework(name: target)
        }
    }
}

private extension XcodeFrameworkReleaseBuild {
    func buildFramework(name: String) throws {
        guard let devicePath = Self.findFrameworkPath(sdk: .ios, name: name),
              let simulatorPath = Self.findFrameworkPath(sdk: .sim, name: name) else {
            return
        }

        let outputPath = Folder.current.path.shellFriendly + "/XCFrameworks/\(name).xcframework"

        let arguments: [String] = [
            "-create-xcframework",
            "-framework \(devicePath)",
            "-framework \(simulatorPath)",
            "-debug-symbols \(devicePath).dSYM",
            "-debug-symbols \(simulatorPath).dSYM",
            "-output \(outputPath)"
        ]

        try XcodeBuildRunner(rawLogPath: .rawBuildLog, logPath: .buildLog).run(
            "NSUnbufferedIO=YES xcodebuild",
            args: arguments
        )
    }

    static func findFrameworkPath(sdk: SDK, name: String) -> String? {
        let buildFolder = Folder.current.path.shellFriendly + .buildFolder
        let frameworkPath = buildFolder + "/\(CONFIG.release)-\(sdk.xcodebuild)/\(name)"

        guard let folder = try? Folder(path: frameworkPath) else {
            return nil
        }

        for subfolder in folder.subfolders.recursive {
            if subfolder.name.contains(".framework") {
                return String(subfolder.path.dropLast())
            }
        }

        return nil
    }
}
