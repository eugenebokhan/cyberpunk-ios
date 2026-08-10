import ProjectDescription

let runtimeFrameworks = [
  "Foundation", "UIKit", "CoreGraphics", "CoreFoundation", "Security", "Metal",
  "GameKit", "GameController", "QuartzCore",
]
let buildTool =
  "/usr/bin/xcrun --sdk macosx swift run --package-path \"$SRCROOT/Packages/GameBuildTools\" --configuration release game-build"

let project = Project(
  name: "Cyberpunk",
  organizationName: "Eugene Bokhan",
  options: .options(automaticSchemesOptions: .disabled),
  packages: [.local(path: "Packages/GameRuntime")],
  settings: .settings(base: [
    "SUPPORTED_PLATFORMS": "iphoneos",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "SWIFT_VERSION": "6.0",
  ]),
  targets: [
    .target(
      name: "RuntimeBridge",
      destinations: [.iPhone],
      product: .dynamicLibrary,
      productName: "libMacShim",
      bundleId: "com.eugenebokhan.cyport.runtime",
      deploymentTargets: .iOS("27.0"),
      infoPlist: nil,
      sources: ["Application/RuntimeBridge.swift"],
      dependencies: [.package(product: "GameRuntime")]
        + runtimeFrameworks.map { .sdk(name: $0, type: .framework) },
      settings: .settings(base: [
        "CODE_SIGNING_ALLOWED": "NO",
        "DYLIB_COMPATIBILITY_VERSION": "9999.0.0",
        "DYLIB_CURRENT_VERSION": "9999.0.0",
        "LD_DYLIB_INSTALL_NAME": "@rpath/libMacShim.dylib",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "OTHER_LDFLAGS": .array(
          ["$(inherited)", "-all_load"]
            + ["Foundation", "UIKit", "CoreGraphics", "Security", "Metal", "GameKit"]
            .map { "-Wl,-reexport_framework,\($0)" }),
      ])
    ),
    .target(
      name: "Cyberpunk",
      destinations: [.iPhone],
      product: .app,
      productName: "Cyberpunk2077",
      bundleId: "com.eugenebokhan.cyport",
      deploymentTargets: .iOS("27.0"),
      infoPlist: .variable("$(DERIVED_FILE_DIR)/GameInfo.plist"),
      resources: ["Application/Resources/DefaultUserSettings.json", "LICENSE"],
      scripts: [
        .pre(
          script: """
            set -eu
            /usr/bin/xcrun --sdk macosx swift run --package-path "$SRCROOT/Packages/GameBuildTools" --configuration release game-build prepare
            """,
          name: "Prepare installed Mac App Store game",
          outputPaths: [
            "$(DERIVED_FILE_DIR)/GameInfo.plist",
            "$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)",
            "$(TARGET_BUILD_DIR)/$(FULL_PRODUCT_NAME)/GameSupport/addonDescriptions.xml",
            "$(TARGET_BUILD_DIR)/$(FULL_PRODUCT_NAME)/AppIcon60x60@2x.png",
            "$(TARGET_BUILD_DIR)/$(FULL_PRODUCT_NAME)/AppIcon60x60@3x.png",
            "$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/libBink2MacArm64.dylib",
            "$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/libGameServicesAppStore.dylib",
            "$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/libREDGalaxy64.dylib",
          ],
          basedOnDependencyAnalysis: false
        ),
        .post(
          script: "\(buildTool) verify \"$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME\"",
          name: "Verify native imports",
          basedOnDependencyAnalysis: false
        ),
      ],
      dependencies: [.target(name: "RuntimeBridge", status: .none)],
      settings: .settings(
        base: [
          "CODE_SIGN_STYLE": "Automatic",
          "CODE_SIGN_ENTITLEMENTS": "Application/Cyberpunk.entitlements",
          "ENABLE_DEBUG_DYLIB": "NO",
          "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES",
          "LD_RUNPATH_SEARCH_PATHS": [
            "$(inherited)", "@executable_path/Frameworks", "/usr/lib/swift",
          ],
        ],
        configurations: [
          .debug(
            name: "Debug",
            settings: ["CODE_SIGN_ENTITLEMENTS": "Application/CyberpunkDebug.entitlements"]),
          .release(name: "Release"),
        ])
    ),
  ],
  schemes: [
    .scheme(
      name: "Cyberpunk",
      buildAction: .buildAction(targets: ["Cyberpunk"]),
      runAction: .runAction(
        configuration: .release,
        attachDebugger: false,
        preActions: [
          .executionAction(
            title: "Install game data",
            scriptText: """
              set -eu
              if [ -z "${TARGET_DEVICE_IDENTIFIER:-}" ]; then
                echo "error: Select your connected iPhone before running Cyberpunk."
                exit 1
              fi
              /usr/bin/xcrun devicectl device install app --device "$TARGET_DEVICE_IDENTIFIER" "$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
              \(buildTool) install-data "$TARGET_DEVICE_IDENTIFIER" "$PRODUCT_BUNDLE_IDENTIFIER"
              """,
            target: "Cyberpunk")
        ],
        executable: "Cyberpunk",
        metalOptions: .options(apiValidation: false)),
      archiveAction: .archiveAction(configuration: .release))
  ],
  additionalFiles: [
    "README.md", "LICENSE", "Application/Info.plist",
    "Application/*.entitlements", "Packages/GameBuildTools/**",
  ]
)
