// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BaseKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BaseKit", targets: ["BaseKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
    ],
    targets: [
        .target(
            name: "BaseKit",
            dependencies: [
                "Clibgit2",
                "CGitShim",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        // C wrappers for the few libgit2 calls Swift can't make directly.
        .target(name: "CGitShim", dependencies: ["Clibgit2"]),
        // libgit2, built from the sources in Vendor/libgit2 (scripts/vendor-libgit2.sh). These
        // defines replace the git2_features.h that libgit2's CMake build would generate: HTTPS
        // through the system's TLS, Apple's CommonCrypto for SHA-256, and no SSH.
        .target(
            name: "Clibgit2",
            path: "Vendor/libgit2",
            sources: ["src/libgit2", "src/util", "deps/llhttp", "deps/xdiff"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src/libgit2"),
                .headerSearchPath("src/util"),
                .headerSearchPath("deps/llhttp"),
                .headerSearchPath("deps/xdiff"),
                .define("LIBGIT2_NO_FEATURES_H"),
                .define("GIT_THREADS"),
                .define("GIT_ARCH_64"),
                .define("GIT_USE_ICONV"),
                .define("GIT_USE_NSEC"),
                .define("GIT_USE_STAT_MTIMESPEC"),
                .define("GIT_USE_FUTIMENS"),
                .define("GIT_REGEX_REGCOMP_L"),
                .define("GIT_QSORT_BSD"),
                .define("GIT_HTTPS"),
                .define("GIT_SECURE_TRANSPORT"),
                .define("GIT_HTTPPARSER_BUILTIN"),
                .define("GIT_SHA1_COLLISIONDETECT"),
                .define("SHA1DC_NO_STANDARD_INCLUDES", to: "1"),
                .define("SHA1DC_CUSTOM_INCLUDE_SHA1_C", to: "\"git2_util.h\""),
                .define("SHA1DC_CUSTOM_INCLUDE_UBC_CHECK_C", to: "\"git2_util.h\""),
                .define("GIT_SHA256_COMMON_CRYPTO"),
                .define("GIT_COMPRESSION_ZLIB"),
                .define("GIT_IO_POLL"),
                // Clang modules make <search.h>'s `struct entry` clash with xdiff's.
                .unsafeFlags(["-fno-modules", "-w"]),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(name: "BaseKitTests", dependencies: ["BaseKit"]),
    ]
)
