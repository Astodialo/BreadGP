# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    foundry.url = "github:shazow/foundry.nix/monthly"; # Use monthly branch for permanent releases
  };

  outputs = { self, nixpkgs, utils, foundry }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ foundry.overlay ];
        };
      in {

        devShell = with pkgs; mkShell {
          buildInputs = [
            # From the foundry overlay
            # Note: Can also be referenced without overlaying as: foundry.defaultPackage.${system}
            foundry-bin
            yarn
            nodejs
            python3
            typescript
            node2nix
            nodePackages.ts-node
            nodePackages.pnpm

            openssl
            pkg-config
            docker

            # ... any other dependencies we need
          ];

          # Decorative prompt override so we know when we're in a dev shell
          shellHook = ''
          '';
        };
      });
}
