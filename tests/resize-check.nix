# Test script for the `diskSize` tests. `diskSize` grows the image while it is
# customized (not at boot), so check the outcome from inside the guest.
#
# `minDiskMiB` must be above the *original* virtual size of the image under test
# and below its size after growing; it is what proves that the disk really grew.
# (Cloud images ship with the root partition already ending at the end of the
# disk, so "the partition reaches the end of the disk" alone holds without any
# resize.) Revisit it if an image's published size changes.
{ minDiskMiB }:
''
  vm.wait_for_unit("multi-user.target")
  vm.succeed("""
    set -eu
    src=$(findmnt -no SOURCE -T / | cut -d[ -f1)
    part=$(basename "$src")
    disk=$(lsblk -no PKNAME "$src" | head -n1)
    start=$(cat /sys/class/block/$part/start)
    size=$(cat /sys/class/block/$part/size)
    disksize=$(cat /sys/class/block/$disk/size)
    echo "disk MiB: $((disksize / 2048))"
    # The disk is larger than the original image...
    [ "$((disksize / 2048))" -ge ${toString minDiskMiB} ]
    # ...the root partition extends to its end (up to the GPT backup tables and
    # alignment, well under 2 MiB)...
    slack=$((disksize - start - size))
    echo "unused sectors at the end of the disk: $slack"
    [ "$slack" -le 4096 ]
    # ...and the root filesystem fills the partition.
    fssize=$(df -B1 --output=size / | tail -n1)
    echo "filesystem bytes: $fssize, partition bytes: $((size * 512))"
    [ "$fssize" -ge $((size * 512 * 9 / 10)) ]
  """)
''
