# Maps a host system to the Linux guest system its VMs run as.
#
# VM tests always run a Linux guest. By default the guest matches the host's own
# architecture (same-arch, hardware-accelerated: KVM on Linux, HVF on darwin), which
# on darwin requires a Linux builder to build the guest closure. Pass an explicit
# `guestSystem` to run a foreign-arch guest instead; QEMU falls back to TCG (software
# emulation) in that case (see generic/default.nix's `accel`).
{ hostSystem, guestSystem ? null }:
let
  defaultGuestSystem = {
    "x86_64-linux" = "x86_64-linux";
    "aarch64-linux" = "aarch64-linux";
    "aarch64-darwin" = "aarch64-linux";
  }.${hostSystem} or (throw ''
    nix-vm-test: unsupported host system '${hostSystem}'.
    Supported host systems: x86_64-linux, aarch64-linux, aarch64-darwin.
  '');
  supportedGuestSystems = [ "x86_64-linux" "aarch64-linux" ];
in
if guestSystem == null then defaultGuestSystem
else if builtins.elem guestSystem supportedGuestSystems then guestSystem
else throw ''
  nix-vm-test: unsupported guest system '${guestSystem}'.
  Supported guest systems: x86_64-linux, aarch64-linux.
''
