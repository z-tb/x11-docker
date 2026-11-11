#!/usr/bin/env python3
"""Create and firewall an isolated docker network.

Usage:
    sudo python3 host-setup-docker-network.py foonet
    sudo python3 host-setup-docker-network.py foonet --allow 192.168.1.53/32

What it does:

1. If the docker network does not exist, it suggests a subnet taken from the
   "default-address-pools" setting in /etc/docker/daemon.json, asks you to
   confirm, then creates the network.

2. It applies host firewall rules so containers on the network cannot reach
   any RFC1918 address (10/8, 172.16/12, 192.168/16) and cannot reach the
   host itself. Internet access is left alone.

3. If the network already exists, it asks (in red) whether to clear the
   existing rules and apply them again.

The rules live in two dedicated iptables chains, so clearing them never
touches any other rules on the host:

    DOCKER-USER -> NI-<name>-F   traffic forwarded out of the container
    INPUT       -> NI-<name>-I   traffic aimed at the host itself
"""

import argparse
import ipaddress
import json
import os
import subprocess
import sys

DEFAULT_DAEMON_JSON = "/etc/docker/daemon.json"

RFC1918_NETWORKS = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

RED = "\033[1;31m"
YELLOW = "\033[1;33m"
GREEN = "\033[1;32m"
RESET = "\033[0m"


# ----------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------

def say(message, color=""):
    """Print a message, optionally in color."""
    print(f"{color}{message}{RESET}" if color else message)


def fail(message):
    """Print an error and stop the program."""
    say(f"error: {message}", RED)
    sys.exit(1)


def run(command, check=True):
    """Run a command and return the finished process.

    With check=True a non-zero exit code raises CalledProcessError.
    """
    return subprocess.run(command, capture_output=True, text=True, check=check)


def ask_yes_no(question, color=""):
    """Ask a y/n question until the user gives a valid answer."""
    while True:
        try:
            answer = input(f"{color}{question} <y|n> {RESET}").strip().lower()
        except EOFError:
            return False
        if answer in ("y", "yes"):
            return True
        if answer in ("n", "no"):
            return False


# ----------------------------------------------------------------------
# Docker network
# ----------------------------------------------------------------------

def network_exists(name):
    """Return True if a docker network with this name exists."""
    return run(["docker", "network", "inspect", name], check=False).returncode == 0


def inspect_networks(ids_or_names):
    """Return the parsed 'docker network inspect' output for the given networks."""
    result = run(["docker", "network", "inspect", *ids_or_names])
    return json.loads(result.stdout)


def get_subnets(network):
    """Return the subnets of one inspected docker network as ip_network objects."""
    subnets = []
    ipam_configs = (network.get("IPAM") or {}).get("Config") or []
    for config in ipam_configs:
        if config.get("Subnet"):
            subnets.append(ipaddress.ip_network(config["Subnet"], strict=False))
    return subnets


def get_bridge_name(network):
    """Return the linux bridge interface name used by a docker network."""
    options = network.get("Options") or {}
    custom_name = options.get("com.docker.network.bridge.name")
    if custom_name:
        return custom_name
    # Docker's default naming: "br-" plus the first 12 characters of the id.
    return "br-" + network["Id"][:12]


def create_network(name, subnet):
    """Create the docker network with a fixed subnet and bridge name."""
    bridge = ("br-" + name)[:15]  # linux interface names max out at 15 chars
    say(f"Creating docker network '{name}' (subnet {subnet}, bridge {bridge})")
    run([
        "docker", "network", "create",
        "--driver", "bridge",
        "--subnet", str(subnet),
        "--opt", f"com.docker.network.bridge.name={bridge}",
        name,
    ])


# ----------------------------------------------------------------------
# Choosing a subnet from daemon.json
# ----------------------------------------------------------------------

def load_address_pools(daemon_json_path):
    """Read default-address-pools from daemon.json.

    Returns a list of (base_network, prefix_length) pairs. For example
    {"base": "172.80.0.0/16", "size": 24} becomes (172.80.0.0/16, 24),
    meaning "hand out /24 networks from inside 172.80.0.0/16".
    """
    try:
        with open(daemon_json_path) as f:
            config = json.load(f)
    except (OSError, ValueError):
        return []

    pools = []
    for entry in config.get("default-address-pools") or []:
        try:
            base = ipaddress.ip_network(entry["base"], strict=False)
            size = int(entry["size"])
        except (KeyError, ValueError, TypeError):
            continue
        pools.append((base, size))
    return pools


def get_used_subnets():
    """Return every IPv4 subnet already used by docker networks or host routes."""
    used = []

    # Subnets of existing docker networks
    network_ids = run(["docker", "network", "ls", "-q"]).stdout.split()
    if network_ids:
        for network in inspect_networks(network_ids):
            used.extend(get_subnets(network))

    # Subnets the host already routes (LAN, VPN, and so on)
    routes = run(["ip", "-4", "-json", "route", "show"], check=False)
    if routes.returncode == 0 and routes.stdout.strip():
        for route in json.loads(routes.stdout):
            try:
                used.append(ipaddress.ip_network(route["dst"], strict=False))
            except (KeyError, ValueError):
                pass  # "default" and similar entries are not networks

    return used


def overlaps_any(candidate, used_subnets):
    """Return True if the candidate overlaps any subnet in the list."""
    for used in used_subnets:
        if used.version == candidate.version and candidate.overlaps(used):
            return True
    return False


def suggest_subnet(pools, used_subnets):
    """Return the first free subnet from the pools, or None if there is none."""
    for base, size in pools:
        if base.version != 4 or size < base.prefixlen or size > 32:
            continue
        for candidate in base.subnets(new_prefix=size):
            if not overlaps_any(candidate, used_subnets):
                return candidate
    return None


def ask_for_cidr(network_name):
    """Ask the user to type a subnet. Returns None if they leave it empty."""
    while True:
        text = input(f"{YELLOW}Enter a subnet CIDR for '{network_name}' "
                     f"(empty to abort): {RESET}").strip()
        if not text:
            return None
        try:
            subnet = ipaddress.ip_network(text)  # strict: rejects host bits
        except ValueError:
            say(f"'{text}' is not a valid network CIDR", YELLOW)
            continue
        if subnet.version == 4:
            return subnet
        say("only IPv4 networks are supported", YELLOW)


def choose_subnet(network_name, daemon_json_path):
    """Pick the subnet for a new network, with the user's confirmation.

    Returns an ip_network, or None if the user declined.
    """
    pools = load_address_pools(daemon_json_path)
    if not pools:
        say(f"No default-address-pools found in {daemon_json_path}", YELLOW)
        return ask_for_cidr(network_name)

    suggestion = suggest_subnet(pools, get_used_subnets())
    if suggestion is None:
        say(f"Every block in {daemon_json_path} is already in use", YELLOW)
        return ask_for_cidr(network_name)

    question = (f"Network '{network_name}' does not exist. "
                f"Create it with subnet {suggestion} (from {daemon_json_path})?")
    if ask_yes_no(question, YELLOW):
        return suggestion
    return None


def warn_if_outside_pools(network, daemon_json_path):
    """Warn when an existing network's subnet is not inside the configured pools."""
    pools = load_address_pools(daemon_json_path)
    if not pools:
        return
    for subnet in get_subnets(network):
        inside = any(base.version == subnet.version and subnet.subnet_of(base)
                     for base, _size in pools)
        if not inside:
            say(f"Subnet {subnet} is not inside the default-address-pools "
                f"in {daemon_json_path}", YELLOW)


# ----------------------------------------------------------------------
# Firewall rules
# ----------------------------------------------------------------------

def iptables(*args, check=True):
    """Run iptables, waiting for the xtables lock if another tool holds it."""
    return run(["iptables", "-w", *args], check=check)


def chain_names(network_name):
    """Return the (forward_chain, input_chain) names for this network."""
    safe = "".join(c if c.isalnum() else "_" for c in network_name)[:20]
    return f"NI-{safe}-F", f"NI-{safe}-I"


def chain_exists(chain):
    return iptables("-L", chain, "-n", check=False).returncode == 0


def jump_exists(parent_chain, bridge, target_chain):
    """Return True if parent_chain already jumps to target_chain for this bridge."""
    result = iptables("-C", parent_chain, "-i", bridge, "-j", target_chain, check=False)
    return result.returncode == 0


def rules_present(network_name, bridge):
    forward_chain, input_chain = chain_names(network_name)
    return (jump_exists("DOCKER-USER", bridge, forward_chain)
            and jump_exists("INPUT", bridge, input_chain))


def remove_chain(parent_chain, target_chain, bridge):
    """Remove the jump into target_chain, then empty and delete the chain."""
    while jump_exists(parent_chain, bridge, target_chain):
        iptables("-D", parent_chain, "-i", bridge, "-j", target_chain)
    if chain_exists(target_chain):
        iptables("-F", target_chain)
        iptables("-X", target_chain)


def clear_rules(network_name, bridge):
    say(f"Clearing existing firewall rules for '{network_name}' ({bridge})")
    forward_chain, input_chain = chain_names(network_name)
    remove_chain("DOCKER-USER", forward_chain, bridge)
    remove_chain("INPUT", input_chain, bridge)


def apply_rules(network_name, bridge, allowed_cidrs):
    """Block RFC1918 and the host for traffic coming from the bridge."""
    if not chain_exists("DOCKER-USER"):
        fail("DOCKER-USER chain not found; is the docker daemon running?")

    say(f"Applying firewall rules for '{network_name}' ({bridge})")
    forward_chain, input_chain = chain_names(network_name)

    # Traffic leaving a container for somewhere else (goes through FORWARD).
    iptables("-N", forward_chain)
    iptables("-A", forward_chain,
             "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT")
    iptables("-A", forward_chain, "-o", bridge, "-j", "ACCEPT")  # same-network traffic
    for cidr in allowed_cidrs:
        iptables("-A", forward_chain, "-d", cidr, "-j", "ACCEPT")
    for cidr in RFC1918_NETWORKS:
        iptables("-A", forward_chain, "-d", cidr,
                 "-j", "REJECT", "--reject-with", "icmp-net-prohibited")
    iptables("-A", forward_chain, "-j", "RETURN")  # everything else (internet) passes
    iptables("-I", "DOCKER-USER", "1", "-i", bridge, "-j", forward_chain)

    # Traffic aimed at the host itself (goes through INPUT).
    iptables("-N", input_chain)
    iptables("-A", input_chain,
             "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT")
    for cidr in allowed_cidrs:
        iptables("-A", input_chain, "-d", cidr, "-j", "ACCEPT")
    iptables("-A", input_chain, "-j", "DROP")
    iptables("-I", "INPUT", "1", "-i", bridge, "-j", input_chain)


# ----------------------------------------------------------------------
# Main program
# ----------------------------------------------------------------------

def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Create an isolated docker network and firewall it from RFC1918.")
    parser.add_argument("network", help="docker network name, for example foonet")
    parser.add_argument("--daemon-json", default=DEFAULT_DAEMON_JSON,
                        help=f"path to daemon.json (default: {DEFAULT_DAEMON_JSON})")
    parser.add_argument("--allow", action="append", default=[], metavar="CIDR",
                        help="CIDR to allow before the RFC1918 block, such as an "
                             "internal DNS server (can be repeated)")
    args = parser.parse_args()

    for cidr in args.allow:
        try:
            ipaddress.ip_network(cidr, strict=False)
        except ValueError:
            parser.error(f"--allow: '{cidr}' is not a valid CIDR")
    return args


def setup_new_network(args):
    """The network does not exist: pick a subnet, create it, apply the rules."""
    subnet = choose_subnet(args.network, args.daemon_json)
    if subnet is None:
        fail(f"network '{args.network}' not created; "
             "refusing to continue without the isolated network")

    create_network(args.network, subnet)
    bridge = get_bridge_name(inspect_networks([args.network])[0])

    clear_rules(args.network, bridge)  # remove leftovers from an older network
    apply_rules(args.network, bridge, args.allow)
    say(f"Network '{args.network}' created and isolated from RFC1918", GREEN)


def refresh_existing_network(args):
    """The network exists: offer to clear and re-apply its rules."""
    network = inspect_networks([args.network])[0]
    bridge = get_bridge_name(network)
    warn_if_outside_pools(network, args.daemon_json)

    question = (f"Network '{args.network}' already exists. "
                "Clear existing firewall rules and re-apply them?")
    if ask_yes_no(question, RED):
        clear_rules(args.network, bridge)
        apply_rules(args.network, bridge, args.allow)
        say(f"Rules re-applied for '{args.network}'", GREEN)
    elif rules_present(args.network, bridge):
        say(f"Keeping existing rules for '{args.network}'")
    else:
        # The user said no, but without the rules the network is not isolated.
        say(f"Rules for '{args.network}' are missing, applying them", YELLOW)
        clear_rules(args.network, bridge)
        apply_rules(args.network, bridge, args.allow)


def main():
    args = parse_arguments()

    if os.geteuid() != 0:
        fail("must run as root (use sudo)")

    try:
        if network_exists(args.network):
            refresh_existing_network(args)
        else:
            setup_new_network(args)
    except FileNotFoundError as error:
        fail(f"required command not found: {error.filename}")
    except subprocess.CalledProcessError as error:
        fail(f"command failed: {' '.join(error.cmd)}\n{error.stderr.strip()}")
    except KeyboardInterrupt:
        sys.exit(130)


if __name__ == "__main__":
    main()

