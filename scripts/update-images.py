#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3Packages.beautifulsoup4 python3Packages.requests nix-prefetch

import re
import requests
import subprocess
import json
from bs4 import BeautifulSoup
from datetime import datetime


def nix_hash(url):
    print(f"[+] Calculating Nix hash for {url}")
    res = subprocess.run(["nix-prefetch-url", url], stdout=subprocess.PIPE)
    return res.stdout.rstrip().decode("utf-8")

def nix_hash_sri(url):
    # `fetchurl { hash = ...; }` wants an SRI hash, unlike `sha256 = ...`, which
    # takes the base32 digest that nix-prefetch-url prints.
    res = subprocess.run(
        ["nix", "hash", "convert", "--hash-algo", "sha256", "--to", "sri", nix_hash(url)],
        stdout=subprocess.PIPE, check=True,
    )
    return res.stdout.rstrip().decode("utf-8")

def get_latest_debian_image(url):
    print(f"[+] Parsing debian index {url}")
    # Step 1: retrieve the latest entry
    page = requests.get(url)
    soup = BeautifulSoup(page.content, "html.parser")
    rows = soup.find_all("tr")
    l = [row.a["href"] for row in rows if row.a]
    # Filtering out non-datetime entries such as "daily" or "latest"
    l = [s for s in l if re.compile("^[0-9]{8}-[0-9]{4}/$").match(s)]
    # Parsing date part of the string
    parsed_l = [(datetime.strptime(s[:8], '%Y%m%d'), s) for s in l]
    latest = max(parsed_l)
    url = f"{url}/{latest[1]}"
    print(f"[+] Parsing latest entry: {url}")

    # Step 2: retrieve images
    page = requests.get(url)
    soup = BeautifulSoup(page.content, "html.parser")
    rows = soup.find_all("tr")
    l = [row.a["href"] for row in rows if row.a]
    res = {}
    for s in l:
        if re.compile("^.*-generic-.*\.qcow2$").match(s):
            if "amd64" in s:
                res["x86_64-linux"] = f"{url}{s}"
            elif "arm64" in s:
                res["aarch64-linux"] = f"{url}{s}"
    return res

"""
Parse the debian cloudimages
"""
def debian_parse():
    bookworm_url = "https://cloud.debian.org/images/cloud/bookworm"
    trixie_url = "https://cloud.debian.org/images/cloud/trixie/daily"
    bookworm = get_latest_debian_image(bookworm_url)
    trixie = get_latest_debian_image(trixie_url)
    res = {}
    for arch in bookworm.keys():
        res[arch] = {
            "12": {
                "name": bookworm[arch],
                "hash": nix_hash(bookworm[arch])

            },
            "13": {
                "name": trixie[arch],
                "hash": nix_hash(trixie[arch])
            }
        }
    return json.dumps(res)

def get_latest_ubuntu_image(url):
    print(f"[+] Parsing ubuntu index {url}")
    # Step 1: retrieve the latest entry
    page = requests.get(url)
    soup = BeautifulSoup(page.content, "html.parser")
    links = soup.find_all("a")
    l = [link["href"] for link in links if re.compile("^release-.*[0-9]{8}/").match(link["href"])]
    parsed_l = [(datetime.strptime(s[8:-1], "%Y%m%d"), s) for s in l]
    latest = max(parsed_l)

    # Step 2: retrieve images
    url = f"{url}{latest[1]}"
    print(f"[+] Parsing latest entry: {url}")
    page = requests.get(url)
    soup = BeautifulSoup(page.content, "html.parser")
    links = soup.find_all("a")
    res = {}
    for link in links:
        if re.compile(".*-server-cloudimg.*\.img$").match(link["href"]):
            link = link["href"]
            if "amd64" in link:
                res["x86_64-linux"] = f"{url}{link}"
            elif "arm64" in link:
                res["aarch64-linux"] = f"{url}{link}"
    return res

def ubuntu_parse():
    oracular_url = "https://cloud-images.ubuntu.com/releases/oracular/"
    noble_url = "https://cloud-images.ubuntu.com/releases/noble/"
    mantic_url = "https://cloud-images.ubuntu.com/releases/23.10/"
    lunar_url = "https://cloud-images.ubuntu.com/releases/23.04/"
    kinetic_url = "https://cloud-images.ubuntu.com/releases/22.10/"
    jammy_url = "https://cloud-images.ubuntu.com/releases/22.04/"
    focal_url = "https://cloud-images.ubuntu.com/releases/focal/"
    resolute_url = "https://cloud-images.ubuntu.com/releases/resolute/"
    oracular = get_latest_ubuntu_image(oracular_url)
    noble = get_latest_ubuntu_image(noble_url)
    mantic = get_latest_ubuntu_image(mantic_url)
    lunar = get_latest_ubuntu_image(lunar_url)
    kinetic = get_latest_ubuntu_image(kinetic_url)
    jammy = get_latest_ubuntu_image(jammy_url)
    focal = get_latest_ubuntu_image(focal_url)
    resolute = get_latest_ubuntu_image(resolute_url)

    res = {}
    def gen_entry_dict(entry):
        return { "name": entry, "hash": nix_hash(entry) }
    for arch in mantic.keys():
        res[arch] = {
            "20_04": gen_entry_dict(focal[arch]),
            "22_04": gen_entry_dict(jammy[arch]),
            "22_10": gen_entry_dict(kinetic[arch]),
            "23_04": gen_entry_dict(lunar[arch]),
            "23_10": gen_entry_dict(mantic[arch]),
            "24_04": gen_entry_dict(noble[arch]),
            "24_10": gen_entry_dict(oracular[arch]),
            "26_04": gen_entry_dict(resolute[arch]),
        }
    return json.dumps(res)

def get_latest_archlinux_release(index_url):
    print(f"[+] Parsing archlinux index {index_url}")
    page = requests.get(index_url)
    soup = BeautifulSoup(page.content, "html.parser")
    links = soup.find_all("a")
    versioned = [
        link["href"].rstrip("/")
        for link in links
        if re.compile(r"^v[0-9]{8}\.[0-9]+/?$").match(link["href"])
    ]
    parsed = [
        (datetime.strptime(v[1:9], "%Y%m%d"), v) for v in versioned
    ]
    return max(parsed)[1]

def archlinux_parse():
    index_url = "https://geo.mirror.pkgbuild.com/images/"
    latest = get_latest_archlinux_release(index_url)
    date_part = latest[1:9]
    release_url = f"{index_url}{latest}/"

    def fetch_sha256(url):
        print(f"[+] Fetching SHA256 for {url}")
        return requests.get(url).text.split()[0]

    url = f"{release_url}Arch-Linux-x86_64-basic-{latest[1:]}.qcow2"
    return json.dumps({
        "x86_64-linux": {
            date_part: {
                "url": url,
                "name": f"Arch-Linux-x86_64-basic-{latest[1:]}.qcow2",
                "hash": nix_hash_sri(url),
            }
        }
    })

def list_links(url):
    """The links of an HTML directory index, or [] if there is no such page."""
    page = requests.get(url)
    if page.status_code != 200:
        return []
    soup = BeautifulSoup(page.content, "html.parser")
    return [link["href"] for link in soup.find_all("a") if link.get("href")]

def load_images(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

FEDORA_RELEASES = "https://dl.fedoraproject.org/pub/fedora/linux/releases/"

def fedora_parse():
    """
    Add the Fedora releases that are missing from fedora/images.json.

    A release's image never changes once it is published, and the releases that
    reached their end of life are moved to the archive, so (unlike the other
    distributions) the existing entries are kept and only new ones are hashed.
    """
    res = load_images("fedora/images.json")
    tracked = [int(v) for images in res.values() for v in images]
    oldest = min(tracked) if tracked else 43
    print(f"[+] Parsing fedora index {FEDORA_RELEASES}")
    releases = sorted(
        int(link.rstrip("/"))
        for link in list_links(FEDORA_RELEASES)
        if re.fullmatch("[0-9]+/", link) and int(link.rstrip("/")) >= oldest
    )
    for release in releases:
        for arch, system in [("x86_64", "x86_64-linux"), ("aarch64", "aarch64-linux")]:
            if str(release) in res.get(system, {}):
                continue
            directory = f"{release}/Cloud/{arch}/images/"
            # Skip the UEFI-UKI variant, which is a different image
            images = [
                link
                for link in list_links(FEDORA_RELEASES + directory)
                if re.fullmatch(rf"Fedora-Cloud-Base-Generic-{release}-[0-9.]+\.{arch}\.qcow2", link)
            ]
            if not images:
                continue
            name = directory + max(images)
            res.setdefault(system, {})[str(release)] = {
                "name": name,
                "hash": nix_hash_sri(FEDORA_RELEASES + name),
            }
    return json.dumps(res)

ROCKY_RELEASES = "https://download.rockylinux.org/pub/rocky/"

def rocky_parse():
    """
    Add the Rocky releases that are missing from rocky/images.json.

    Like Fedora's, a release's image never changes once it is published, so the
    existing entries are kept and only new releases are hashed. Only the current
    minor releases are listed under pub/; the superseded ones move to vault/, which
    is why the entries already in the file point there.
    """
    res = load_images("rocky/images.json")
    print(f"[+] Parsing rocky index {ROCKY_RELEASES}")
    versions = [
        link.rstrip("/")
        for link in list_links(ROCKY_RELEASES)
        if re.fullmatch(r"[0-9]+\.[0-9]+/", link)
    ]
    for version in versions:
        key = version.replace(".", "_")
        for arch, system in [("x86_64", "x86_64-linux"), ("aarch64", "aarch64-linux")]:
            if key in res.get(system, {}):
                continue
            directory = f"{ROCKY_RELEASES}{version}/images/{arch}/"
            images = [
                link
                for link in list_links(directory)
                if re.fullmatch(
                    rf"Rocky-[0-9]+-GenericCloud-Base-{re.escape(version)}-[0-9]{{8}}\.[0-9]+\.{arch}\.qcow2",
                    link,
                )
            ]
            if not images:
                continue
            url = directory + max(images)
            res.setdefault(system, {})[key] = {
                "url": url,
                "name": f"Rocky-{version}-GenericCloud.{arch}.qcow2",
                "sha256": nix_hash(url),
            }
    return json.dumps(res)

if __name__ == '__main__':
    ubuntu_json = ubuntu_parse()
    with open("ubuntu.json", "w") as f:
        f.write(ubuntu_json)
    debian_json = debian_parse()
    with open("debian.json", "w") as f:
        f.write(debian_json)
    archlinux_json = archlinux_parse()
    with open("archlinux.json", "w") as f:
        f.write(archlinux_json)
    fedora_json = fedora_parse()
    with open("fedora.json", "w") as f:
        f.write(fedora_json)
    rocky_json = rocky_parse()
    with open("rocky.json", "w") as f:
        f.write(rocky_json)
