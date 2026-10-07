{ generic, guestPkgs, lib, guestSystem }:
let
  imagesJSON = lib.importJSON ./images.json;
  fetchImage = image: guestPkgs.fetchurl {
    inherit (image) hash;
    url = image.url;
  };
  images = lib.mapAttrs (k: v: fetchImage v) (imagesJSON.${guestSystem} or {});
  makeVmTestForImage = imageID: image: { testScript, sharedDirs ? {}, diskSize ? null, extraPathsToRegister ? [ ], memorySize ? null, cpus ? null }: generic.makeVmTest {
    name = "vm-test-archlinux_${imageID}";
    inherit testScript sharedDirs memorySize cpus;
    image = prepareArchlinuxImage {
      inherit diskSize extraPathsToRegister;
      originalImage = image;
    };
  };

  # The image is customized offline in a throwaway VM (no libguestfs), so this is
  # the same on every architecture. Arch's basic image is GPT with BIOS boot + EFI
  # and a btrfs root.
  prepareArchlinuxImage = { originalImage, diskSize, extraPathsToRegister ? [ ] }:
    generic.customizeImageInVM {
      name = "${originalImage.name}-nix-vm-test.qcow2";
      inherit originalImage diskSize;
      rootModules = [ "btrfs" "xor" "raid6_pq" "zstd_compress" ];
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

        # arch-boxes enables a pacman-init and keyring-sync pair that need the
        # network to run first-boot key initialization
        rm -f "$mnt/etc/systemd/system/pacman-init.service"

        # Don't spawn ttys on these devices, they are used for test instrumentation
        systemctl --root="$mnt" mask serial-getty@${generic.serialConsole}.service serial-getty@hvc0.service

        # We have no reliable network in the test VMs
        systemctl --root="$mnt" mask sshd.service sshd.socket

        # arch-boxes enables systemd-time-wait-sync which blocks time-sync.target ->
        # multi-user.target forever when NTP is unreachable
        systemctl --root="$mnt" mask systemd-time-wait-sync.service

        # The pacman-init / keyring-sync units also need the network
        systemctl --root="$mnt" mask pacman-init.service archlinux-keyring-wkd-sync.service archlinux-keyring-wkd-sync.timer

        # Skip waiting for the network to be "online"
        systemctl --root="$mnt" mask systemd-networkd-wait-online.service

        # arch-boxes installs GRUB; systemd-boot-update is pointless
        systemctl --root="$mnt" mask systemd-boot-update.service

        # Drop GRUB's interactive timeout so the VM doesn't wait at the menu, and
        # route the kernel console to the serial line the test driver reads.
        if [ -f "$mnt/boot/grub/grub.cfg" ]; then
          sed -i 's/^set timeout=.*/set timeout=0/' "$mnt/boot/grub/grub.cfg"
          sed -i 's|\(linux\s\+/boot/vmlinuz-linux[^\n]*\)|\1 console=tty0 console=${generic.serialConsole}|' "$mnt/boot/grub/grub.cfg"
        fi
        if [ -f "$mnt/etc/default/grub" ]; then
          sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$mnt/etc/default/grub"
          sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 console=tty0 console=${generic.serialConsole}"|' "$mnt/etc/default/grub"
        fi

        systemctl --root="$mnt" enable backdoor.service
      '';
    };
in {
  inherit images prepareArchlinuxImage;
} // lib.mapAttrs makeVmTestForImage images
