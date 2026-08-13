{ nixpkgs,   # The nixpkgs source
  system     # The *host* system (where QEMU and the test driver run)
}:
let
  inherit (nixpkgs) lib;

  hostSystem = system;
  supportedGuestSystems = [ "x86_64-linux" "aarch64-linux" ];

  # `hostPkgs`  runs the driver/QEMU (darwin on a Mac); `guestPkgs` is always a
  # Linux set used for the guest image and anything executed inside the VM.
  # Built lazily per possible guest arch, so only the arch(es) actually
  # requested by a test call get evaluated/built.
  hostPkgs = import nixpkgs { system = hostSystem; };
  guestPkgsFor = lib.genAttrs supportedGuestSystems
    (gs: if gs == hostSystem then hostPkgs else import nixpkgs { system = gs; });

  genericFor = lib.genAttrs supportedGuestSystems
    (gs: hostPkgs.callPackage ./generic {
      inherit nixpkgs hostPkgs hostSystem;
      guestPkgs = guestPkgsFor.${gs};
      guestSystem = gs;
    });
  ubuntu = hostPkgs.callPackage ./ubuntu { inherit genericFor guestPkgsFor hostSystem; };
  debian = hostPkgs.callPackage ./debian { inherit genericFor guestPkgsFor hostSystem; };
  fedora = hostPkgs.callPackage ./fedora { inherit genericFor guestPkgsFor hostSystem; };
  rocky = hostPkgs.callPackage ./rocky { inherit genericFor guestPkgsFor hostSystem; };
  # Function that can be used when defining inline modules to get better location
  # reporting in module-system errors.
  # Usage example:
  #   { _file = "${printAttrPos (builtins.unsafeGetAttrPos "a" { a = null; })}: inline module"; }
  nixos = "${nixpkgs}/nixos";
in {
  inherit ubuntu debian fedora rocky;
}
