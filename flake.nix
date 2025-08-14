{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zig2nix = {
      url = "github:Cloudef/zig2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      zig-overlay,
      zig2nix,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      zig-version = "0.14.1";
      zig = zig-overlay.packages.${system}.${zig-version};

      env = zig2nix.outputs.zig-env.${system} { };

      makePackages = target: targetSuffix: {
        "dispatch-server${targetSuffix}" = env.package (
          {
            pname = "orphie-dispatch-server";
            version = "0.1.0";
            src = ./.;

            nativeBuildInputs = [ pkgs.protobuf ];

            zigBuildZon = ./build.zig.zon;
            zigBuildZonLock = ./build.zig.zon2json-lock;

            zigBuildFlags = [ "orphie_dispatch_server" ];
          }
          // (if target != null then { zigTarget = target; } else { })
        );

        "game-server${targetSuffix}" = env.package (
          {
            pname = "orphie-game-server";
            version = "0.1.0";
            src = ./.;

            nativeBuildInputs = [ pkgs.protobuf ];

            zigBuildZon = ./build.zig.zon;
            zigBuildZonLock = ./build.zig.zon2json-lock;

            zigBuildFlags = [ "orphie_game_server" ];
          }
          // (if target != null then { zigTarget = target; } else { })
        );
      };

      linuxPackages = makePackages null "";
      windowsPackages = makePackages "x86_64-windows" "-windows";
    in
    {
      packages.${system} =
        linuxPackages
        // windowsPackages
        // {
          default = pkgs.symlinkJoin {
            name = "orphie-zs-servers";
            paths = [
              self.packages.${system}.dispatch-server
              self.packages.${system}.game-server
            ];
          };

          windows = pkgs.symlinkJoin {
            name = "orphie-zs-servers-windows";
            paths = [
              self.packages.${system}.dispatch-server-windows
              self.packages.${system}.game-server-windows
            ];
          };
        };

      devShells.${system}.default = pkgs.callPackage (
        { mkShell }:
        mkShell {
          nativeBuildInputs = [
            zig
            pkgs.zls
            pkgs.unzip
            pkgs.protobuf
          ];
        }
      ) { };
    };
}
