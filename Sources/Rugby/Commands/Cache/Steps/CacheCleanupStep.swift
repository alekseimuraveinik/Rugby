//
//  CacheCleanupStep.swift
//  Rugby
//
//  Created by Vyacheslav Khorkov on 31.01.2021.
//  Copyright © 2021 Vyacheslav Khorkov. All rights reserved.
//

import Files
import Foundation

struct CacheCleanupStep: Step {
    struct Input {
        let scheme: String?
        let targets: Set<String>
        let products: [String]
    }

    let verbose: Int
    let isLast: Bool
    let progress: Printer

    private let command: Cache
    private let metrics: Metrics

    init(command: Cache, metrics: Metrics, logFile: File, isLast: Bool = false) {
        self.command = command
        self.metrics = metrics
        self.verbose = command.flags.verbose
        self.isLast = isLast
        self.progress = RugbyPrinter(title: "Clean up",
                                     logFile: logFile,
                                     verbose: verbose,
                                     quiet: command.flags.quiet,
                                     nonInteractive: command.flags.nonInteractive)
    }

    func run(_ input: Input) throws {
        let (targets, products) = (input.targets, Set(input.products))
        var hasChanges = false

        let project = try progress.spinner("Read project") {
            try ProjectProvider.shared.readProject(.podsProject)
        }

        if !command.keepSources {
            progress.print("Remove sources from project".yellow, level: .vv)
            hasChanges = true
            project.removeSources(pods: targets, fromGroup: .podsGroup)
            try project.removeSources(fromTargets: targets)
        }

        progress.print("Remove frameworks".yellow, level: .vv)
        hasChanges = project.removeFrameworks(products: products) || hasChanges

        progress.print("Remove products".yellow, level: .vv)
        if project.removeFrameworkPaths(products: products) {
            hasChanges = true
        }

        progress.print("Remove build target".yellow, level: .vv)
        if let target = input.scheme, project.removeTarget(name: target) {
            hasChanges = true
        }

        progress.print("Remove built pods".yellow, level: .vv)
        // Adding all remaining targets to exclude. It needs for adding transitive dependencies explicitly.
        let exclude = Set(project.pbxproj.main.targets.map(\.name))
            .subtracting(targets)
            .union(command.exclude)
        var removeBuiltPods = project.removeDependencies(names: targets, exclude: Array(exclude))
        targets.forEach {
            removeBuiltPods = project.removeTarget(name: $0) || removeBuiltPods
        }

        if hasChanges || removeBuiltPods {
            // Remove schemes if has changes (it should be changes in targets)
            progress.print("Remove schemes".yellow, level: .vv)
            try project.removeSchemes(pods: targets, projectPath: .podsProject)

            try progress.spinner("Save project") {
                project.pbxproj.main.set(buildSettingsKey: .rugbyPatched, value: String.yes)
                try project.write(pathString: .podsProject, override: true)
            }

            metrics.projectSize.after = (try Folder.current.subfolder(at: .podsProject)).size()
            metrics.compileFilesCount.after = project.pbxproj.buildFiles.count
            metrics.targetsCount.after = project.pbxproj.main.targets.count
        }

        progress.print("Remove built frameworks".yellow, level: .vv)
        let buildFolder = try Folder.current.subfolder(at: .buildFolder)
        for folder in buildFolder.subfolders {
            if folder.name.hasPrefix(CONFIG.debug) || folder.name.hasPrefix(CONFIG.release) {
                try folder.delete()
            }
        }

        done()
    }
}
