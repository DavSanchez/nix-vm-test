{ nixpkgs,   # The nixpkgs source
  system      # The host system (e.g. "x86_64-linux" or "aarch64-darwin")
}:
let
  pkgs = import nixpkgs { inherit system; };
  inherit (nixpkgs) lib;

  # Map a host system to the guest/image system used by the per-distro
  # default.nix files. All supported distros ship x86_64 and aarch64 cloud
  # images, so a Darwin/aarch64 host runs aarch64 guests.
  guestSystem = {
    "x86_64-linux"   = "x86_64-linux";
    "aarch64-darwin" = "aarch64-linux";
  }.${system} or (throw "nix-vm-test: unsupported host system: ${system}");

  generic = pkgs.callPackage ./generic { inherit nixpkgs guestSystem; };
  ubuntu = pkgs.callPackage ./ubuntu { inherit generic system guestSystem; };
  debian = pkgs.callPackage ./debian { inherit generic system guestSystem; };
  fedora = pkgs.callPackage ./fedora { inherit generic system guestSystem; };
  rocky = pkgs.callPackage ./rocky { inherit generic system guestSystem; };
in {
  inherit ubuntu debian fedora rocky;
}
