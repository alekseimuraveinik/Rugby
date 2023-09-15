//
//  FilePatcher.swift
//  Rugby
//
//  Created by Vyacheslav Khorkov on 03.03.2021.
//  Copyright © 2021 Vyacheslav Khorkov. All rights reserved.
//

import Files
import Foundation

struct FilePatcher {
    /// Replacing content of each file by regex criteria in selected folder.
    func replace(_ lookup: String,
                 with replace: String,
                 inFilesByRegEx fileRegEx: String,
                 folder: Folder) throws {
        let regex = try fileRegEx.regex()
        for file in folder.files.recursive where file.path.match(regex) {
            try autoreleasepool {
                var content = try file.readAsString()
                content = content.replacingOccurrences(of: lookup, with: replace, options: .regularExpression)
                try file.write(content)
            }
        }
    }

    func updateFrameworkSearchPaths(inFilesByRegEx fileRegEx: String, folder: Folder) throws {
        let regex = try fileRegEx.regex()
        for file in folder.files.recursive where file.path.match(regex) {
            try updateFrameworkSearchPaths(for: file)
        }
    }

    func fixSwiftInterfaceIfNeeded(for targets: Set<String>) throws {
        for target in targets {
            try fixSwiftInterfaceIfNeeded(for: target)
        }
    }
}

private extension FilePatcher {
    func updateFrameworkSearchPaths(for file: File) throws {
        var content = try file.readAsString()

        let frameworkPaths = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { line in
                if #available(macOS 13, *) {
                    return line.contains(.relativeToPodsRootPath)
                } else {
                    return line.range(of: String.relativeToPodsRootPath) != nil
                }
            }

        for path in frameworkPaths {
            let frameworkFolderPath = String.cacheFolder(at: .relativeToPodsRootPath) + "/"
            let frameworkName = path
                .replacingOccurrences(of: frameworkFolderPath, with: "")
                .filter { $0 != "\"" }
                .components(separatedBy: "/")
                .first

            guard let frameworkName = frameworkName else { continue }

            let frameworkPath = frameworkFolderPath + frameworkName
            let xcFrameworkPath = makeXCFrameworkPath(for: frameworkName)
            let newPath = path.replacingOccurrences(of: frameworkPath, with: xcFrameworkPath)

            content = content.replacingOccurrences(of: path, with: newPath)
        }

        content = content.replacingOccurrences(of: "$(CONFIGURATION)", with: CONFIG.release)

        if let range = content.range(of: String.frameworkSearchPaths) {
            let xcFrameworkPlatform = """
            XCFRAMEWORK_PLATFORM_iphonesimulator = ios-arm64_x86_64-simulator
            XCFRAMEWORK_PLATFORM_iphoneos = ios-arm64
            XCFRAMEWORK_PLATFORM = $(XCFRAMEWORK_PLATFORM_$(PLATFORM_NAME))\n
            """

            content.insert(contentsOf: xcFrameworkPlatform, at: range.lowerBound)
        }

        try autoreleasepool {
            try file.write(content)
        }
    }

    func makeXCFrameworkPath(for target: String) -> String {
        .relativeToPodsRootPath + "XCFrameworks/\(target).xcframework/${XCFRAMEWORK_PLATFORM}"
    }

    func fixSwiftInterfaceIfNeeded(for name: String) throws {
        let xcFrameworkPath = Folder.current.path.shellFriendly + "/XCFrameworks/\(name).xcframework"
        guard let folder = try? Folder(path: xcFrameworkPath) else { return }

        var paths: [String] = []

        for subfolder in folder.subfolders.recursive {
            for file in subfolder.files {
                if file.name.contains(".private.swiftinterface") {
                    paths.append(file.path)
                }
            }
        }

        for path in paths {
            guard let file = try? File(path: path),
                  var content = try? file.readAsString() else {
                continue
            }

            content = content.replacingOccurrences(of: "\(name).\(name)", with: "module_reference")
            content = content.replacingOccurrences(of: "\(name).", with: "")
            content = content.replacingOccurrences(of: "module_reference", with: name)

            if name == "DataDomeAlamofire" {
                content = content.replacingOccurrences(of: "DataDomeSDK.", with: "")
            }

            try autoreleasepool {
                try file.write(content)
            }
        }
    }
}
