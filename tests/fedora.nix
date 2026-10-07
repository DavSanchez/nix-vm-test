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
    (n: v: pkgs.lib.nameValuePair "${n}-multi-user-test" (test lib.fedora.${n}))
    lib.fedora.images;
in {
  resizeImage = (lib.fedora."43" {
    sharedDirs = {};
    testScript = import ./resize-check.nix { minDiskMiB = 5632; };
    diskSize = "+1G";
  }).sandboxed;

  sharedDirTest = let
    dir1 = pkgs.runCommandNoCC "dir1" {} ''
      mkdir -p $out
      echo "hello1" > $out/somefile1
    '';
    dir2 = pkgs.runCommandNoCC "dir2" {} ''
      mkdir -p $out
      echo "hello2" > $out/somefile2
    '';
  in (lib.fedora."43" {
    sharedDirs = {
      dir1 = {
        source = dir1;
        target = "/tmp/dir1";
      };
      dir2 = {
        source = dir2;
        target = "/tmp/dir2";
      };
    };
    testScript = ''
      vm.wait_for_unit("multi-user.target")
      vm.succeed('ls /tmp/dir1')
      vm.succeed('test "$(cat /tmp/dir1/somefile1)" == "hello1"')
      vm.succeed('test "$(cat /tmp/dir2/somefile2)" == "hello2"')
    '';
  }).sandboxed;
} //
runTestOnEveryImage multiUserTest //
package.fedora.images
