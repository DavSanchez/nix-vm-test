{ generic, guestPkgs, lib, guestSystem }:
let
  imagesJSON = lib.importJSON ./images.json;
  fetchImage = image: guestPkgs.fetchurl {
    inherit (image) hash;
    url = "https://download.fedoraproject.org/pub/fedora/linux/releases/${image.name}";
  };
  # Fedora only ships x86_64 images here, so on an aarch64 guest (e.g. darwin)
  # `imagesJSON.${guestSystem}` is absent and this cleanly resolves to no tests.
  images = lib.mapAttrs (k: v: fetchImage v) (imagesJSON.${guestSystem} or {});
  makeVmTestForImage = imageID: image: { testScript, sharedDirs ? {}, diskSize ? null, extraPathsToRegister ? [ ], selinuxEnforcing ? false, memorySize ? null, cpus ? null }: generic.makeVmTest {
    name = "vm-test-fedora_${imageID}";
    inherit testScript sharedDirs memorySize cpus;
    image = prepareFedoraImage {
      inherit diskSize extraPathsToRegister selinuxEnforcing;
      originalImage = image;
    };
  };

  # The image is customized offline in a throwaway VM (no libguestfs), so this is
  # the same on every architecture.
  prepareFedoraImage = { originalImage, diskSize, extraPathsToRegister ? [ ], selinuxEnforcing ? false }:
    generic.customizeImageInVM {
      name = "${originalImage.name}-nix-vm-test.qcow2";
      inherit originalImage diskSize;
      # The root filesystem is a btrfs subvolume named `root` (next to `home` and `var`).
      mountOptions = "subvol=root";
      rootModules = [ "btrfs" "xor" "raid6_pq" "zstd_compress" ];
      nativeBuildInputs = [ guestPkgs.attr ];
      script = ''
        # Clear the root password
        sed -i 's/^root:[^:]*:/root::/' "$mnt/etc/shadow"

        groupadd --root "$mnt" nixbld

        # Copy the service files in under fixed names, since otherwise they end
        # up in the VM with their paths including the nix hash
        install -m755 ${generic.backdoorScript} "$mnt/usr/bin/backdoorScript"
        # Patch the store-path shebang to /bin/bash.
        sed -i 's|^#!/nix/store/.*|#!/bin/bash|' "$mnt/usr/bin/backdoorScript"
        install -m644 ${generic.backdoor { scriptPath = "/usr/bin/backdoorScript"; }} "$mnt/etc/systemd/system/backdoor.service"
        install -m644 ${generic.mountStore { pathsToRegister = extraPathsToRegister; }} "$mnt/etc/systemd/system/mount-store.service"

        # Don't spawn ttys on these devices, they are used for test instrumentation
        # and we have no network in the test VMs, avoid an error on bootup
        systemctl --root="$mnt" mask \
          serial-getty@${generic.serialConsole}.service serial-getty@hvc0.service \
          ssh.service ssh.socket

        # Retrieve guest interface conf via DHCP. The NIC is named differently per
        # architecture (ens4 on x86_64, enp0s3 on aarch64), so match any ethernet.
        mkdir -p "$mnt/etc/systemd/network"
        cat > "$mnt/etc/systemd/network/80-nixvmtest.network" << EOF
        [Match]
        Name=en*

        [Network]
        DHCP=yes
        EOF

        # Everything is configured offline, and without a datasource cloud-init would
        # spend minutes probing unreachable metadata endpoints at boot.
        mkdir -p "$mnt/etc/cloud"
        touch "$mnt/etc/cloud/cloud-init.disabled"

        systemctl --root="$mnt" enable backdoor.service

        ${if selinuxEnforcing then ''
          # Files written from here carry no SELinux labels. Label the ones the boot
          # needs by hand rather than relabeling the whole filesystem on first boot.
          label() { setfattr -h -n security.selinux -v "system_u:object_r:$1:s0" "''${@:2}"; }
          label bin_t "$mnt/usr/bin/backdoorScript"
          label shadow_t "$mnt/etc/shadow"
          label systemd_unit_file_t "$mnt"/etc/systemd/system/{backdoor,mount-store}.service
        '' else ''
          sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' "$mnt/etc/selinux/config"
        ''}
      '';
    };
in {
  inherit images prepareFedoraImage;
} // lib.mapAttrs makeVmTestForImage images
