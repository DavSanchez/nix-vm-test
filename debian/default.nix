{ generic, pkgs, lib, system, guestSystem }:
let
  imagesJSON = lib.importJSON ./images.json;
  fetchImage = image: pkgs.fetchurl {
    sha256 = image.hash;
    url = image.name;
  };
  images = lib.mapAttrs (k: v: fetchImage v) imagesJSON.${guestSystem};
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  makeVmTestForImage = imageID: image: { testScript, sharedDirs ? {}, diskSize ? null, extraPathsToRegister ? [ ], memorySize ? null, cpus ? null }: generic.makeVmTest {
    name = "vm-test-debian_${imageID}";
    inherit system testScript sharedDirs memorySize cpus;
    # On Linux hosts the image is prepared at build time with
    # virt-customize (unchanged behavior). On Darwin hosts the
    # stock cloud image is shipped unmodified and cloud-init
    # configures the guest at first boot.
    image = if isDarwin then image
            else prepareDebianImage {
              inherit diskSize extraPathsToRegister;
              hostPkgs = pkgs;
              originalImage = image;
            };
    cloudInitSeed = if isDarwin then
      prepareDebianCloudInitSeed {
        inherit diskSize extraPathsToRegister;
        hostPkgs = pkgs;
      }
    else null;
  };
  # Build-time image prep (Linux hosts). Bakes the systemd units
  # and per-distro tweaks into the qcow2 with `virt-customize`.
  # Kept exactly as it was before the cloud-init refactor.
  prepareDebianImage = { hostPkgs, originalImage, diskSize, extraPathsToRegister ? [ ]}:
    let
      pkgs = hostPkgs;
      resultImg = "./image.qcow2";
    in
    pkgs.runCommand "${originalImage.name}-nix-vm-test.qcow2" { } ''
      # We will modify the VM image, so we need a mutable copy
      install -m777 ${originalImage} ${resultImg}

      # Copy the service files here, since otherwise they end up in the VM
      # with their paths including the nix hash
      cp ${generic.backdoor {}} backdoor.service
      cp ${generic.mountStore { pathsToRegister = extraPathsToRegister; }} mount-store.service
      cp ${generic.resizeService} resizeguest.service

      # virt-resize depends on qemu-img, which is part of the qemu
      # derivation
      ${lib.optionalString (diskSize != null) ''
        export PATH="${pkgs.qemu}/bin:$PATH"
        qemu-img resize ${resultImg} ${diskSize}
      ''}

      #export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1
      ${lib.concatStringsSep "  \\\n" [
        "${pkgs.guestfs-tools}/bin/virt-customize"
        "-a ${resultImg}"
        "--smp 2"
        "--memsize 256"
        "--no-network"
        "--copy-in backdoor.service:/etc/systemd/system"
        "--copy-in mount-store.service:/etc/systemd/system"
        "--copy-in resizeguest.service:/etc/systemd/system"
        "--run"
        (pkgs.writeShellScript "run-script" ''
          # Clear the root password
          passwd -d root

          # Don't spawn ttys on these devices, they are used for test instrumentation
          systemctl mask serial-getty@ttyS0.service
          systemctl mask serial-getty@hvc0.service

          # We have no network in the test VMs, avoid an error on bootup
          systemctl mask ssh.service
          systemctl mask ssh.socket

          # Retrieve guest interface conf via DHCP
          cat << EOF >> /etc/systemd/network/80-ens4.network
          [Match]
          Name=ens4

          [Network]
          DHCP=yes
          EOF

          ${lib.optionalString (diskSize != null) ''
            systemctl enable resizeguest.service
          ''}
          systemctl enable backdoor.service

        '')
      ]};

      cp ${resultImg} $out
    '';
  # Boot-time image prep (Darwin hosts). Builds a cloud-init
  # NoCloud seed that drops the same systemd units into the
  # guest and runs the equivalent per-distro setup. The 9P
  # `mountStore` service mounted at runtime resolves the
  # host-correct nix-store paths referenced from the units.
  prepareDebianCloudInitSeed = { hostPkgs, diskSize, extraPathsToRegister }:
    let
      userData = ''
        #cloud-config
        write_files:
          - path: /etc/systemd/system/backdoor.service
            permissions: '0644'
            owner: root:root
            content: |
        ${generic.indentString (generic.backdoor {} + "\n") "              "}
          - path: /etc/systemd/system/mount-store.service
            permissions: '0644'
            owner: root:root
            content: |
        ${generic.indentString (generic.mountStore { pathsToRegister = extraPathsToRegister; } + "\n") "              "}
          ${lib.optionalString (diskSize != null) ''
          - path: /etc/systemd/system/resizeguest.service
            permissions: '0644'
            owner: root:root
            content: |
        ${generic.indentString (generic.resizeService + "\n") "              "}
          ''}
          - path: /etc/systemd/network/80-ens4.network
            permissions: '0644'
            owner: root:root
            content: |
              [Match]
              Name=ens4

              [Network]
              DHCP=yes

        runcmd:
          - passwd -d root
          - systemctl mask serial-getty@ttyS0.service serial-getty@hvc0.service
          - systemctl mask ssh.service ssh.socket
          - systemctl daemon-reload
          - systemctl enable backdoor.service mount-store.service
          ${lib.optionalString (diskSize != null)
              "- systemctl enable resizeguest.service"}
      '';
      metaData = ''
        instance-id: iid-${lib.substring 0 16 (builtins.hashString "sha256" userData)}
        local-hostname: vm
      '';
    in
    generic.mkCloudInitSeed {
      name = "debian-cloud-init-seed";
      inherit userData metaData;
    };
in {
  inherit images prepareDebianImage prepareDebianCloudInitSeed;
} // lib.mapAttrs makeVmTestForImage images
