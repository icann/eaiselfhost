#!/usr/bin/env python3
#
# EAI mail "toaster"
# December 2024
#
# Copyright 2024 Standcore LLC

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:

# 1. Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.

# 2. Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
# WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# argument is mail name, optional host name
# A and MX and SPF are mandatory
# AAAA should be correct
# rDNS recommended

import dns.resolver
import ipaddress
import requests

debug = False

# returns v4 or v6 address you connected from
ip4url = "https://ip4.me/api/"
ip6url = "https://ip6.me/api/"

def getips():
    """
    find our global IP addressses
    """
    ipv4 = ipv6 = None

    r = requests.get(ip4url)
    if r.status_code == 200:
        tv = r.text.split(',')
        if tv[0] == 'IPv4':
            ipv4 = tv[1]
        else:
            print(f"strange IPv4 address {r.text}")

    r = requests.get(ip6url)
    if r.status_code == 200:
        tv = r.text.split(',')
        if tv[0] == 'IPv6':
            ipv6 = tv[1]
        elif tv[0] != 'IPv4':      
            print(f"strange IPv6 address {r.text}")

    return (ipv4, ipv6)

def checkhost(domain: str, ipv4: str, ipv6: str | None):
    """
    check that the domain has the right IP addresses
    """
    ok = okr = False
    try:
        r = dns.resolver.resolve(domain, 'A')
        for rr in r:
            if rr.rdtype == rr.rdtype.A:
                if rr.address == ipv4:
                    print(f"Found valid A record '{domain}. A {rr}'")
                    ok = True
                else:
                    print(f"Warning: {domain} has address {rr.address} which is not this server.")
    except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.NoNameservers):
        pass
    # check reverse
    ip4rev = ipaddress.ip_address(ipv4).reverse_pointer
    if debug:
        print(f"check {ip4rev}")
    try:
        r = dns.resolver.resolve(ip4rev, 'PTR')
        for rr in r:
            if rr.rdtype == rr.rdtype.PTR:
                if rr.target.to_text(True).lower() == domain:
                    print(f"Found valid IPv4 PTR record '{rr}'")
                    okr = True
                else:
                    print(f"Warning: {ipv4} has name {rr.target} which is not this server's name.")
    except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.NoNameservers):
        pass

    if not ok:
        print("Error: no DNS A record for this server.  Add this record in your DNS and then rerun this script.")
        print(f"\n   {domain}. IN A {ipv4}\n")
    
    if not okr:
        print("Warning: no IPv4 reverse DNS for this server.")
        print(f"Have your hosting provider set it to {domain}.")

    if ipv6:
        ok6 = ok6r = False
        try:
            r = dns.resolver.resolve(domain, 'AAAA')
            for rr in r:
                if rr.rdtype == rr.rdtype.AAAA:
                    if rr.address == ipv6:
                        ok6 = True
                        print(f"found valid AAAA record '{domain}. AAAA {rr}'")
                    else:
                        print(f"Warning: {domain} has address {rr.address} which is not this server.")
        except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.NoNameservers):
            pass
        # check reverse
        ip6rev = ipaddress.ip_address(ipv6).reverse_pointer
        if debug:
            print(f"check {ip6rev}")
        try:
            r = dns.resolver.resolve(ip6rev, 'PTR')
            for rr in r:
                if rr.rdtype == rr.rdtype.PTR:
                    if rr.target.to_text(True).lower() == domain:
                        print(f"Found valid IPv6 PTR record '{rr}'")
                        ok6r = True
                    else:
                        print(f"Warning: {ipv6} has name {rr.target} which is not this server's name.")
        except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.NoNameservers):
            pass
        if not ok6:
            print("Error: no DNS AAAA record for this server.  Add this record in your DNS and then rerun this script.")
            print(f"\n   {domain}. IN AAAA {ipv6}\n")
            ok = False
        if not ok6r:
            print("Warning: no IPv6 reverse DNS for this server.\n"
                "Have your hosting provider set it to {domain}.")
    return ok
    
def checkmail(domain: str, hostdomain: str):
    """
    check that the domain has the right MX
    """
    ok = False

    try:
        r = dns.resolver.resolve(domain, 'MX')
        for rr in r:
            if rr.rdtype == rr.rdtype.MX:
                # get host name
                rx = rr.exchange
                if rx.is_absolute():
                    rn = rx.to_text()[:-1]
                else:
                    rn = rx.to_text()
                if rn == hostdomain:
                    ok = True
                    print(f"Found valid MX record '{domain}. {rr}'")
                else:
                    print(f"Warning: {domain} has MX {rr} which does not refer to this server {rn} {hostdomain}.")
    except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.NoNameservers):
        pass
    if not ok:
        print("Error: no DNS MX record for this server.  Add this record in your DNS and then rerun this script.")
        print(f"\n   {domain}. IN MX 10 {hostdomain}.\n")
    
    return ok

def checkspf(domain: str):
    """
    see if there is a plausible SPF record
    """
    ok = False
    seenone = False
    try:
        r = dns.resolver.resolve(domain, 'TXT')
        for rr in r:
            if rr.rdtype == rr.rdtype.TXT:
                bs = b''.join(rr.strings)
                if bs.startswith(b'v=spf1'):
                    if seenone:
                        print(f"Error: more than one SPF record. Delete the excess ones.")
                        ok = False
                        continue
                    seenone = True
                    if b'mx' in bs:
                        ok = True   # close enough
                        print(f"Found valid SPF record '{bs.decode()}'")
                    else:
                        print(f"Error: SPF record looks wrong '{bs.decode()}'")
    except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer, dns.resolver.NoNameservers):
        pass
    if not ok:
        print("Error: no valid DNS SPF record for this server.  Add this record in your DNS and then rerun this script.")
        print(f"""\n   {domain}. IN TXT "v=spf1 mx ~all"\n""")
    return ok

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description='Update user accounts')
    parser.add_argument('-d', action='store_true', help="debug info");
    parser.add_argument('--dkim', type=str, help="DKIM key record");
    parser.add_argument('maildomain', type=str, help="Mail domain name");
    parser.add_argument('hostdomain', type=str, nargs='?', help="Host domain name, default same as mail");
    args = parser.parse_args();

    debug = args.d

    maildomain = args.maildomain
    if args.hostdomain:
        hostdomain = args.hostdomain
    else:
        hostdomain = maildomain

    # get our IP addresses
    (ipv4, ipv6) = getips()
    if debug:
        print("ipv4",ipv4,"ipv6",ipv6)

    # does the host have a/aaaa records ?
    ok = checkhost(hostdomain, ipv4, ipv6)

    # does the mail have an MX
    ok &= checkmail(maildomain, hostdomain)
    ok &= checkspf(maildomain)

    exit(0 if ok else 1)
