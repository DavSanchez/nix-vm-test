final: prev:

let
  inherit (prev.stdenv.hostPlatform) system;
  inherit (prev) lib;
  hostSystem = system;

  supportedGuestSystems = [ "x86_64-linux" "aarch64-linux" ];

  # On a Linux host the guest packages are just `final`; on darwin we need a
  # Linux package set for the guest image and in-VM binaries. Built lazily per
  # possible guest arch (Nix attrsets are lazy per-attribute), so only the
  # arch(es) actually requested by a test call get evaluated/built.
  guestPkgsFor = lib.genAttrs supportedGuestSystems
    (gs: if gs == hostSystem then final else import prev.path { system = gs; });

  genericFor = lib.genAttrs supportedGuestSystems
    (gs: import ./generic {
      inherit lib;
      hostPkgs = final;
      guestPkgs = guestPkgsFor.${gs};
      inherit hostSystem;
      guestSystem = gs;
      nixpkgs = prev.path;
    });

  ubuntu = prev.callPackage ./ubuntu { inherit genericFor guestPkgsFor hostSystem; };
  debian = prev.callPackage ./debian { inherit genericFor guestPkgsFor hostSystem; };
  fedora = prev.callPackage ./fedora { inherit genericFor guestPkgsFor hostSystem; };
  rocky = prev.callPackage ./rocky { inherit genericFor guestPkgsFor hostSystem; };
in

{
  testers = prev.testers or { } // {
    nonNixOSDistros = prev.testers.nonNixOSDistros or {} // {
      inherit debian ubuntu fedora rocky;
    };
  };
}
