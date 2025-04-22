# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    foundry.url = "github:shazow/foundry.nix/monthly"; # Use monthly branch for permanent releases
  };

  outputs = { self, nixpkgs, utils, foundry, rust-overlay }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ 
            foundry.overlay
            rust-overlay.overlays.default
           ];
        };
      in {

        devShell = with pkgs; mkShell {
          buildInputs = [
            # From the foundry overlay
            # Note: Can also be referenced without overlaying as: foundry.defaultPackage.${system}
            openssl
            pkg-config
            solc

            foundry-bin

            # rust
            (rust-bin.fromRustupToolchainFile ./rust-toolchain.toml)
            taplo #toml formatter & lsp
            cargo-watch
            cargo-deny
            cargo-audit
            cargo-update
            cargo-edit
            cargo-outdated
            cargo-license
            cargo-tarpaulin
            cargo-cross
            cargo-zigbuild
            cargo-nextest
            cargo-spellcheck
            cargo-modules
            cargo-bloat
            cargo-unused-features
            cargo-feature
            cargo-features-manager
            bacon
            evcxr #rust repl

            # ... any other dependencies we need
          ];

          # Decorative prompt override so we know when we're in a dev shell
          shellHook = ''
            export PS1="[dev] $PS1"
          '';
        };
      });
}
