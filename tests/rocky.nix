{ pkgs, package, system }:
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
  # The VMs have no network, so ssh is masked to keep it from failing at boot.
  sshMasked = (lib.rocky."10_1" {
    sharedDirs = {};
    testScript = ''
      vm.wait_for_unit("multi-user.target")
      vm.succeed('test "$(systemctl is-enabled sshd.service 2>&1 || true)" = masked')
      vm.succeed('test "$(systemctl is-enabled sshd.socket 2>&1 || true)" = masked')
    '';
  }).sandboxed;
} //
runTestOnEveryImage multiUserTest //
package.rocky.images
