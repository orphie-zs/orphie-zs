{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    zig-overlay,
  }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    zig-version = "0.14.1";
  in
  {
    devShells.${system}.default =
      pkgs.callPackage (
        { mkShell }:
        mkShell {
          nativeBuildInputs = [
            zig-overlay.packages.${system}.${zig-version}
            pkgs.zls
            pkgs.unzip
            pkgs.protobuf
          ];
        }
      ) { };
  };
}
