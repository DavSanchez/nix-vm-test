{ pkgs, package, system }:

let
  inherit (pkgs) lib;
  isDarwin = system == "aarch64-darwin";
in
{
  # Smoke test: confirms the guest is the expected architecture
  # (aarch64 on Apple Silicon, x86_64 on Linux). The
  # host-conditional image prep (virt-customize on Linux, cloud-init
  # on Darwin) means this test exercises the full pipeline end to
  # end on whichever host it runs.
  archRouting = (package.ubuntu."22_04" {
    sharedDirs = {};
    testScript = ''
      vm.wait_for_unit("multi-user.target")
      vm.wait_for_unit("cloud-init.target")
      ${lib.optionalString isDarwin
        ''vm.succeed('test "$(uname -m)" = "aarch64"')''}
      ${lib.optionalString (!isDarwin)
        ''vm.succeed('test "$(uname -m)" = "x86_64"')''}
    '';
  }).sandboxed;

  # Multi-user boot smoke test on aarch64-darwin. Verifies the
  # cloud-init seed + 9P nix-store mount + backdoor service all
  # come up cleanly on Apple Silicon.
  darwinMultiUser = (package.ubuntu."22_04" {
    sharedDirs = {};
    testScript = ''
      vm.wait_for_unit("multi-user.target")
      vm.wait_for_unit("cloud-init.target")
      vm.succeed('test "$(uname -m)" = "aarch64"')
    '';
  }).sandboxed;
}
