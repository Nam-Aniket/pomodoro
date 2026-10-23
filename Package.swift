// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "PomodoroCore"),
        .executableTarget(name: "Pomodoro", dependencies: ["PomodoroCore"],
                          linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("WebKit")]),
        .executableTarget(name: "pomodoro-check", dependencies: ["PomodoroCore"]),
    ]
)
