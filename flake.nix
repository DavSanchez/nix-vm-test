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
      # On aarch64-darwin the per-image test runners depend on
      # `pkgs.guestfs-tools` (Linux-only) for image preparation, so
      # we expose an empty attribute set for that system. The lib
      # output above still evaluates on darwin, so the API surface
      # is in place; running actual VM tests on darwin requires a
      # cloud-init based image preparation path, tracked as a
      # follow-up to issue 97.
      checks = let
        checksFor = system:
          if system == "aarch64-darwin" then { }
          else import ./tests {
            package = (mkPkgs system).testers.nonNixOSDistros;
            pkgs = mkPkgs system;
            inherit system;
          };
      in builtins.listToAttrs (map
        (system: { name = system; value = checksFor system; })
        supportedSystems);
    };
}
