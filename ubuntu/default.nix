{ generic, guestPkgs, lib, guestSystem }:
let
  imagesJSON = lib.importJSON ./images.json;
  fetchImage = image: guestPkgs.fetchurl {
    sha256 = image.hash;
    url = image.name;
  };
  images = lib.mapAttrs (k: v: fetchImage v) (imagesJSON.${guestSystem} or {});

  makeVmTestForImage = imageID: image: { testScript, sharedDirs ? {}, diskSize ? null, extraPathsToRegister ? [ ], memorySize ? null, cpus ? null }: generic.makeVmTest {
    name = "vm-test-ubuntu_${imageID}";
    inherit testScript sharedDirs memorySize cpus;
    image = prepareUbuntuImage {
      inherit diskSize extraPathsToRegister;
      originalImage = image;
    };
  };

  # The image is customized offline in a throwaway VM (no libguestfs), so this is
  # the same on x86_64 and aarch64.
  prepareUbuntuImage = { originalImage, diskSize, extraPathsToRegister ? [ ] }:
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

        # Don't spawn ttys on these devices, they are used for test instrumentation.
        # Also speed up the boot process (snapd), and, since we have no network in
        # the test VMs, avoid an error on bootup (ssh).
        systemctl --root="$mnt" mask \
          serial-getty@${generic.serialConsole}.service serial-getty@hvc0.service \
          snapd.service snapd.socket snapd.seeded.service \
          ssh.service ssh.socket

        # Disable TTY usage in sudo.
        # Otherwise, using sudo spawns a new pty, causing the test-driver to
        # receive mixed stdout and stderr when processing command output.
        # The driver only expects base64-encoded stdout, so extra stderr data
        # can break the output parsing.
        mkdir -p "$mnt/etc/sudoers.d"
        cat > "$mnt/etc/sudoers.d/disable-pty" << EOF
        Defaults !requiretty
        Defaults !use_pty
        EOF
        chmod 440 "$mnt/etc/sudoers.d/disable-pty"

        # Retrieve guest interface conf via DHCP. The NIC is named differently per
        # architecture (ens4 on x86_64, enp0s3 on aarch64), so match any ethernet.
        cat >> "$mnt/etc/netplan/99_config.yaml" << EOF
        network:
          version: 2
          renderer: networkd
          ethernets:
            nixvmtest:
              match:
                name: "en*"
              dhcp4: true
        EOF

        # Everything is configured offline, and without a datasource cloud-init would
        # spend minutes probing unreachable metadata endpoints at boot.
        mkdir -p "$mnt/etc/cloud"
        touch "$mnt/etc/cloud/cloud-init.disabled"

        systemctl --root="$mnt" enable backdoor.service
      '';
    };
in {
  inherit prepareUbuntuImage;
  images = images;
} // lib.mapAttrs makeVmTestForImage images
