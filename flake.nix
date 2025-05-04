{
  description = "simple rust flake";

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

    aarch64-pkgs = import nixpkgs {
      inherit system;
      crossSystem = {
        config = "aarch64-unknown-linux-gnu";
      };
    };

    aarch64-cc = "${aarch64-pkgs.stdenv.cc}/bin/aarch64-unknown-linux-gnu-cc";
  in {
    overlays.default = final: prev: {
      rustToolchain =
        prev.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
    };

    devShell.${system} = pkgs.mkShell {
      buildInputs = with pkgs; [
        rustToolchain
        alsa-lib
        pkg-config
        openssl
        cargo-watch
        systemfd
        qemu
        aarch64-pkgs.stdenv.cc
        aarch64-pkgs.alsa-lib
      ];

      PKG_CONFIG_ALLOW_CROSS = "1";
      PKG_CONFIG_PATH = "/usr/lib/aarch64-linux-gnu/pkgconfig";
      PKG_CONFIG_LIBDIR = "/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig";
      CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = aarch64-cc;

      RUSTFLAGS = "-C link-args=-Wl,--dynamic-linker=/lib/ld-linux-aarch64.so.1";

      shellHook = ''
        export PATH=$PATH:$HOME/.cargo/bin
      '';
    };
  };
}
