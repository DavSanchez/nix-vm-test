final: prev:

let
  inherit (prev.stdenv.hostPlatform) system;
  guestSystem = {
    "x86_64-linux"   = "x86_64-linux";
    "aarch64-darwin" = "aarch64-linux";
  }.${system} or (throw "nix-vm-test: unsupported host system: ${system}");
  generic = import ./generic {
    inherit (prev) lib;
    pkgs = final;
    nixpkgs = prev.path;
    inherit guestSystem;
  };
  ubuntu = prev.callPackage ./ubuntu { inherit generic system guestSystem; };
  debian = prev.callPackage ./debian { inherit generic system guestSystem; };
  fedora = prev.callPackage ./fedora { inherit generic system guestSystem; };
  rocky = prev.callPackage ./rocky { inherit generic system guestSystem; };
in

{
  testers = prev.testers or { } // {
    nonNixOSDistros = prev.testers.nonNixOSDistros or {} // {
      inherit debian ubuntu fedora rocky;
    };
  };
}
