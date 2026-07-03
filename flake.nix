{
  description = "Nix-VM-Test, re-use the NixOS VM integration test infrastructure on Ubuntu, Debian and Fedora";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      mkPkgs = system: import nixpkgs {
        overlays = [ self.overlays.default ];
        localSystem = system;
      };
    in
    {
      overlays.default = import ./overlay.nix;

      # Per-system test runners (ubuntu, debian, fedora, rocky).
      lib = builtins.listToAttrs (map
        (system: {
          name = system;
          value = (mkPkgs system).testers.nonNixOSDistros;
        })
        supportedSystems);

      # Per-system test derivations used by `nix flake check`.
      #
      # Image preparation is host-conditional (see each per-distro
      # `default.nix`): virt-customize on Linux, cloud-init at boot
      # on Darwin. Both paths produce a runnable VM, so the same
      # tests work on both hosts.
      checks = builtins.listToAttrs (map
        (system: {
          name = system;
          value = import ./tests {
            package = (mkPkgs system).testers.nonNixOSDistros;
            pkgs = mkPkgs system;
            inherit system;
          };
        })
        supportedSystems);
    };
}
