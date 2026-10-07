{ generic, guestPkgs, lib, guestSystem }:
let
  imagesJSON = lib.importJSON ./images.json;
  fetchImage = image: guestPkgs.fetchurl {
    inherit (image) sha256;
    url = image.url;
  };

  # Rocky/RHEL 8.x aarch64 kernels are built with 64 KB memory pages. Not every
  # aarch64 CPU implements that translation granule (notably Apple Silicon, which
  # only supports 4 KB/16 KB) — on one that doesn't, the kernel's EFI stub refuses
  # to boot ("64 KB granular kernel is not supported by your CPU") and the VM just
  # hangs. This is a guest-architecture concern, not a darwin-specific one (e.g. an
  # aarch64-linux host with a similarly-limited CPU would hit it too), so filter
  # for any aarch64 guest rather than only when the host happens to be darwin.
  imagesForSystem = imagesJSON.${guestSystem} or { };
  supportedImages =
    if generic.guestIsAarch64
    then lib.filterAttrs (name: _: !(lib.hasPrefix "8_" name)) imagesForSystem
    else imagesForSystem;
  images = lib.mapAttrs (k: v: fetchImage v) supportedImages;

  # Lock repositories to the vault mirror for the image's own minor version, so
  # dnf operations against first-party repos keep working even after that point
  # release is superseded — every image in rocky/images.json already points at
  # `vault/rocky`, so this isn't hypothetical, it's the state of every image we
  # ship. Safe to apply to every repo file since a fresh RESF image ships no
  # non-first-party repos. Kept as plain text (rather than a derivation) because
  # it runs inside a chroot of the image, where no nix store paths are visible.
  rockyFixReposScriptText = ''
    rockyRepoFiles=( $(find /etc/yum.repos.d -type f 2>/dev/null) )
    for repoFile in "''${rockyRepoFiles[@]}"; do
      sed -i 's@.*mirrorlist=@#mirrorlist=@g' "''${repoFile}" # disable mirrorlist
      sed -i 's@.*baseurl=@baseurl=@g' "''${repoFile}" # switch to fastly CDN

      # `pub/rocky` is for non-EoL, `vault/rocky` is for EoL
      sed -i 's@$contentdir@vault/rocky@g' "''${repoFile}"
      sed -i 's@pub/rocky@vault/rocky@g' "''${repoFile}"

      # all this to not pollute the current environment with $VERSION_ID
      (export $(cat /etc/os-release | grep '^VERSION_ID=' | sed -e 's/"//g') && sed -i "s@\$releasever@''${VERSION_ID}@g" "''${repoFile}")
    done
    # change the value of the `contentdir` DNF variable
    [ -f /etc/dnf/vars/contentdir ] && sed -i 's@pub/rocky@vault/rocky@g' /etc/dnf/vars/contentdir
  '';

  makeVmTestForImage = imageID: image: { testScript, sharedDirs ? {}, diskSize ? null, extraPathsToRegister ? [ ], memorySize ? null, cpus ? null }: generic.makeVmTest {
    name = "vm-test-rocky_${imageID}";
    inherit testScript sharedDirs memorySize cpus;
    image = prepareRockyImage {
      inherit diskSize extraPathsToRegister;
      originalImage = image;
    };
  };

  # The image is customized offline in a throwaway VM (no libguestfs), so this is
  # the same on x86_64 and aarch64. RHEL clones disable the 9p filesystem in their
  # kernels, so there is no mounted nix store: the backdoor script is a standalone
  # /bin/bash script copied into /usr/bin.
  prepareRockyImage = { originalImage, diskSize, extraPathsToRegister ? [ ] }:
    generic.customizeImageInVM {
      name = "${originalImage.name}-nix-vm-test.qcow2";
      inherit originalImage diskSize;
      # The root filesystem is XFS.
      rootModules = [ "xfs" ];
      script = ''
        # Clear the root password
        sed -i 's/^root:[^:]*:/root::/' "$mnt/etc/shadow"

        groupadd --root "$mnt" nixbld

        # Copy the service files in under fixed names, since otherwise they end
        # up in the VM with their paths including the nix hash
        install -m755 ${generic.backdoorScript} "$mnt/usr/bin/backdoorScript"
        # Patch the store-path shebang to /bin/bash (there is no mounted store here).
        sed -i 's|^#!/nix/store/.*|#!/bin/bash|' "$mnt/usr/bin/backdoorScript"
        install -m644 ${generic.backdoor { scriptPath = "/usr/bin/backdoorScript"; withMountedStore = false; }} "$mnt/etc/systemd/system/backdoor.service"

        # Don't spawn ttys on these devices, they are used for test instrumentation
        # and we have no network in the test VMs, avoid an error on bootup
        systemctl --root="$mnt" mask \
          serial-getty@${generic.serialConsole}.service serial-getty@hvc0.service \
          sshd.service

        # Retrieve guest interface conf via DHCP. The NIC is named differently per
        # architecture (ens4 on x86_64, enp0s3 on aarch64), so match any ethernet.
        mkdir -p "$mnt/etc/systemd/network"
        cat > "$mnt/etc/systemd/network/80-nixvmtest.network" << EOF
        [Match]
        Name=en*

        [Network]
        DHCP=yes
        EOF

        # (a clean PATH: the one inherited from this VM only has nix store paths)
        chroot "$mnt" /usr/bin/env -i PATH=/usr/bin:/usr/sbin /bin/bash -c ${lib.escapeShellArg rockyFixReposScriptText}

        # Files written from here carry no SELinux labels, which an enforcing policy
        # would deny the backdoor service. Booting permissive is enough for a test VM
        # (and avoids a full relabel + reboot on first boot).
        sed -i 's/^SELINUX=.*/SELINUX=permissive/' "$mnt/etc/selinux/config"

        # Everything is configured offline, and without a datasource cloud-init would
        # spend minutes probing unreachable metadata endpoints at boot.
        mkdir -p "$mnt/etc/cloud"
        touch "$mnt/etc/cloud/cloud-init.disabled"

        systemctl --root="$mnt" enable backdoor.service
      '';
    };
in {
  inherit images prepareRockyImage;
} // lib.mapAttrs makeVmTestForImage images
