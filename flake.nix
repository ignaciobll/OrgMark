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
              simulatorSdk
              src
              system
              xcodeBaseDir
              ;
          }
        );
    in
    {
      packages = forDarwinSystems (
        { pkgs, simulatorSdk, src, xcodeBaseDir, ... }:
        let
          xcodeWrapper = pkgs.xcodeenv.composeXcodeWrapper { inherit xcodeBaseDir; };
        in
        rec {
          default = orgmark-ios;

          orgmark-ios = pkgs.xcodeenv.buildApp {
            name = "orgmark-ios";
            inherit src xcodeBaseDir;
            sdk = simulatorSdk;
            target = "OrgMark";
            nativeBuildInputs = [ xcodeWrapper ];
            __noChroot = true;

            xcodeFlags = "-project OrgMarkiPad/OrgMark.xcodeproj -derivedDataPath \"$TMPDIR/DerivedData\" -clonedSourcePackagesDirPath \"$TMPDIR/SourcePackages\"";

            preBuild = ''
              mkdir -p "$TMPDIR/DerivedData" "$TMPDIR/SourcePackages"

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

      devShells = forDarwinSystems (
        { pkgs, xcodeBaseDir, ... }:
        let
          xcodeWrapper = pkgs.xcodeenv.composeXcodeWrapper { inherit xcodeBaseDir; };
        in
        {
          default = pkgs.mkShell {
            packages = [ xcodeWrapper ];

            shellHook = ''
              cat <<'EOF'
              OrgMark Nix shell
              - xcodebuild comes from the host Xcode wrapper
              - build with: nix build .#orgmark-ios --option sandbox relaxed
              - override Xcode with: XCODE_BASE_DIR=/Applications/Xcode-beta.app
              - override SDK with: IOS_SIMULATOR_SDK=iphonesimulator17.5
              EOF
            '';
          };
        }
      );
    };
}
