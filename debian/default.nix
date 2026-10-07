{ generic, guestPkgs, lib, guestSystem }:
let
  imagesJSON = lib.importJSON ./images.json;
  fetchImage = image: guestPkgs.fetchurl {
    sha256 = image.hash;
    url = image.name;
  };
  images = lib.mapAttrs (k: v: fetchImage v) (imagesJSON.${guestSystem} or {});

  makeVmTestForImage = imageID: image: { testScript, sharedDirs ? {}, diskSize ? null, extraPathsToRegister ? [ ], memorySize ? null, cpus ? null }: generic.makeVmTest {
    name = "vm-test-debian_${imageID}";
    inherit testScript sharedDirs memorySize cpus;
    image = prepareDebianImage {
      inherit diskSize extraPathsToRegister;
      originalImage = image;
    };
  };

  # The image is customized offline in a throwaway VM (no libguestfs), so this is
  # the same on x86_64 and aarch64.
  prepareDebianImage = { originalImage, diskSize, extraPathsToRegister ? [ ] }:
    generic.customizeImageInVM {
      name = "${originalImage.name}-nix-vm-test.qcow2";
      inherit originalImage diskSize;
      script = ''
        # Clear the root password
        sed -i 's/^root:[^:]*:/root::/' "$mnt/etc/shadow"

        # Copy the service files in under fixed names, since otherwise they end
        # up in the VM with their paths including the nix hash
        install -m644 ${generic.backdoor {}} "$mnt/etc/systemd/system/backdoor.service"
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
      '';
    };
in {
  inherit images prepareDebianImage;
} // lib.mapAttrs makeVmTestForImage images
