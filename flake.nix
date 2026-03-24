{
  description = "Build the OrgMark iPad app with nixpkgs xcodeenv";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      darwinSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forDarwinSystems =
        f:
        lib.genAttrs darwinSystems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
            composeXcodeWrapper = import "${nixpkgs.outPath}/pkgs/development/mobile/xcodeenv/compose-xcodewrapper.nix" {
              inherit (pkgs) lib stdenv writeShellScriptBin;
            };
            buildApp = import "${nixpkgs.outPath}/pkgs/development/mobile/xcodeenv/build-app.nix" {
              inherit (pkgs) lib stdenv;
              inherit composeXcodeWrapper;
            };
            envOr =
              name: default:
              let
                value = builtins.getEnv name;
              in
              if value != "" then value else default;
            xcodeBaseDir = envOr "XCODE_BASE_DIR" "/Applications/Xcode.app";
            simulatorSdk = envOr "IOS_SIMULATOR_SDK" "iphonesimulator";
            src = pkgs.lib.cleanSource ./.;
          in
          f {
            inherit
              pkgs
              buildApp
              composeXcodeWrapper
              simulatorSdk
              src
              system
              xcodeBaseDir
              ;
          }
        );
      mkBuildScript =
        {
          pkgs,
          composeXcodeWrapper,
          simulatorSdk,
          xcodeBaseDir,
          ...
        }:
        let
          xcodeWrapper = composeXcodeWrapper { inherit xcodeBaseDir; };
        in
        pkgs.writeShellApplication {
          name = "build-orgmark-ios";
          runtimeInputs = [ xcodeWrapper ];
          text = ''
            set -euo pipefail

            repo_root="$PWD"
            build_dir="''${BUILD_DIR:-$repo_root/build/ios-simulator}"
            source_packages_dir="''${SOURCE_PACKAGES_DIR:-''${TMPDIR:-/tmp}/orgmark-source-packages}"
            home_dir="''${ORGMARK_XCODE_HOME:-''${TMPDIR:-/tmp}/orgmark-xcode-home}"
            sdk_name="''${IOS_SIMULATOR_SDK:-${simulatorSdk}}"

            export HOME="$home_dir"
            export CFFIXED_USER_HOME="$HOME"
            export XDG_CACHE_HOME="$HOME/.cache"
            export SIMULATOR_DEVICE_SET_PATH="$HOME/Library/Developer/CoreSimulator/Devices"

            mkdir -p \
              "$build_dir" \
              "$source_packages_dir" \
              "$XDG_CACHE_HOME" \
              "$HOME/Library/Caches/org.swift.swiftpm/manifests" \
              "$HOME/Library/Caches/com.apple.dt.Xcode/Downloads" \
              "$HOME/Library/Caches/com.apple.dt.xcodebuild" \
              "$HOME/Library/Developer/Xcode/DerivedData" \
              "$HOME/Library/Developer/CoreSimulator/Devices"

            xcodebuild -resolvePackageDependencies \
              -project OrgMarkiPad/OrgMark.xcodeproj \
              -target OrgMark \
              -clonedSourcePackagesDirPath "$source_packages_dir"

            rm -rf "$build_dir"
            mkdir -p "$build_dir"

            xcodebuild \
              -project OrgMarkiPad/OrgMark.xcodeproj \
              -target OrgMark \
              -configuration Debug \
              -sdk "$sdk_name" \
              TARGETED_DEVICE_FAMILY="1, 2" \
              ONLY_ACTIVE_ARCH=NO \
              CODE_SIGNING_ALLOWED=NO \
              CODE_SIGNING_REQUIRED=NO \
              CODE_SIGN_IDENTITY="" \
              -clonedSourcePackagesDirPath "$source_packages_dir" \
              CONFIGURATION_BUILD_DIR="$build_dir"

            printf 'Built OrgMark iOS simulator app in %s\n' "$build_dir"
          '';
        };
    in
    {
      packages = forDarwinSystems (
        { buildApp, composeXcodeWrapper, pkgs, simulatorSdk, src, xcodeBaseDir, ... }:
        let
          xcodeWrapper = composeXcodeWrapper { inherit xcodeBaseDir; };
          buildOrgMarkIos = mkBuildScript {
            inherit pkgs composeXcodeWrapper simulatorSdk xcodeBaseDir;
          };
        in
        rec {
          default = buildOrgMarkIos;

          build-orgmark-ios = buildOrgMarkIos;

          orgmark-ios = buildApp {
            name = "orgmark-ios";
            inherit src xcodeBaseDir;
            sdk = simulatorSdk;
            target = "OrgMark";
            nativeBuildInputs = [ xcodeWrapper ];
            __noChroot = true;

            xcodeFlags = "-project OrgMarkiPad/OrgMark.xcodeproj -clonedSourcePackagesDirPath \"$TMPDIR/SourcePackages\"";

            preBuild = ''
              export HOME="$TMPDIR/home"
              export CFFIXED_USER_HOME="$HOME"
              export XDG_CACHE_HOME="$TMPDIR/cache"
              export SIMULATOR_DEVICE_SET_PATH="$HOME/Library/Developer/CoreSimulator/Devices"

              mkdir -p \
                "$TMPDIR/SourcePackages" \
                "$XDG_CACHE_HOME" \
                "$HOME/Library/Caches/org.swift.swiftpm/manifests" \
                "$HOME/Library/Caches/com.apple.dt.Xcode/Downloads" \
                "$HOME/Library/Caches/com.apple.dt.xcodebuild" \
                "$HOME/Library/Developer/Xcode/DerivedData" \
                "$HOME/Library/Developer/CoreSimulator/Devices"

              xcodebuild -resolvePackageDependencies \
                -project OrgMarkiPad/OrgMark.xcodeproj \
                -target OrgMark \
                -clonedSourcePackagesDirPath "$TMPDIR/SourcePackages"
            '';

            meta = {
              description = "OrgMark iPad app build for the iOS simulator";
              homepage = "https://github.com/casouri/OrgMark";
              platforms = pkgs.lib.platforms.darwin;
            };
          };
        }
      );

      apps = forDarwinSystems (
        { pkgs, composeXcodeWrapper, simulatorSdk, xcodeBaseDir, ... }:
        let
          buildOrgMarkIos = mkBuildScript {
            inherit pkgs composeXcodeWrapper simulatorSdk xcodeBaseDir;
          };
        in
        {
          default = {
            type = "app";
            program = "${buildOrgMarkIos}/bin/build-orgmark-ios";
          };
          build-orgmark-ios = {
            type = "app";
            program = "${buildOrgMarkIos}/bin/build-orgmark-ios";
          };
        }
      );

      devShells = forDarwinSystems (
        { pkgs, composeXcodeWrapper, xcodeBaseDir, ... }:
        let
          xcodeWrapper = composeXcodeWrapper { inherit xcodeBaseDir; };
        in
        {
          default = pkgs.mkShell {
            packages = [ xcodeWrapper ];

            shellHook = ''
              cat <<'EOF'
              OrgMark Nix shell
              - xcodebuild comes from the host Xcode wrapper
              - CI-friendly build: nix run .#build-orgmark-ios --impure
              - experimental derivation: nix build .#orgmark-ios --impure --option sandbox false
              - override Xcode with: XCODE_BASE_DIR=/Applications/Xcode-beta.app
              - override SDK with: IOS_SIMULATOR_SDK=iphonesimulator17.5
              EOF
            '';
          };
        }
      );
    };
}
