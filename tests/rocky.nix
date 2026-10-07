{ pkgs, package, guestPkgs, system }:
let
  lib = package;
  multiUserTest = runner: (runner {
    sharedDirs = {};
    testScript = ''
      vm.wait_for_unit("multi-user.target")
    '';
  }).sandboxed;
  runTestOnEveryImage = test:
    pkgs.lib.mapAttrs'
    (n: v: pkgs.lib.nameValuePair "${n}-multi-user-test" (test lib.rocky.${n}))
    lib.rocky.images;
in {
  resizeImage = (lib.rocky."10_1" {
    sharedDirs = {};
    testScript = import ./resize-check.nix { minDiskMiB = 10752; };
    diskSize = "+1G";
  }).sandboxed;
} //
runTestOnEveryImage multiUserTest //
package.rocky.images
