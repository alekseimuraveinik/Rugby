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

        arguments.append("-config \(CONFIG.release.shellFriendly)")
        arguments.append("| tee " + .rawBuildLog)

        try XcodeBuildRunner(rawLogPath: .rawBuildLog, logPath: .buildLog).run(
            "NSUnbufferedIO=YES xcodebuild",
            args: arguments
        )
    }
}
