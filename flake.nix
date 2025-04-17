{
  description = "A basic Rust flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [rust-overlay.overlays.default self.overlays.default];
    };
  in {
    overlays.default = final: prev: {
      rustToolchain = let
        rust = prev.rust-bin;
      in
        if builtins.pathExists ./rust-toolchain.toml
        then rust.fromRustupToolchainFile ./rust-toolchain.toml
        else if builtins.pathExists ./rust-toolchain
        then rust.fromRustupToolchainFile ./rust-toolchain
        else
          rust.stable.latest.default.override {
            extensions = ["rust-src" "rust-analyzer" "rustfmt"];
          };
    };

    devShell.${system} = let
      targetName = {
        musl = "aarch64-unknown-linux-gnu";
      };

      pkgsCross = builtins.mapAttrs (name: value:
        import pkgs.path {
          system = system;
          crossSystem = {
            config = value;
          };
        })
      targetName;

      ccPkgs = builtins.mapAttrs (name: value: value.stdenv.cc) pkgsCross;
    in
      pkgs.mkShell {
        buildInputs = with pkgs;
          [
            rustToolchain
            rust-analyzer
            cmake
            pkg-config
            openssl
            cargo-deny
            cargo-edit
            cargo-watch
            systemfd
            qemu
          ]
          ++ builtins.attrValues ccPkgs;

        CARGO_BUILD_TARGET = let
          toolchainStr = builtins.readFile ./rust-toolchain.toml;
          targets = (builtins.fromTOML toolchainStr).toolchain.targets;
        in
          builtins.head targets;

        RUST_SRC_PATH = "${pkgs.rustToolchain}/lib/rustlib/src/rust/library";

        shellHook = ''
          export PATH=$PATH:$HOME/.cargo/bin
        '';
      };
  };
}
