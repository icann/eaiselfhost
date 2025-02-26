#!/usr/bin/env python3
#
# EAI mail "toaster"
# Februrary 2025
#
# Copyright 2025 Standcore LLC

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

# argument is domain name
# opt args are postfix and dovecot config files
# postfix file, need entry for both A- and U-labels
#
# mailbox@domain users/mailboxN/Maildir/
#
# dovecot file, mailboxN since it doesn't allow 8 bit logins
#
# mailboxN:{PLAIN}password::::/home/mailuser/mailboxes/mailboxN

import readline
import re
import idna

debug = False
mailuser = "mailuser"   # username/group for mailboxes

def makeusers(aname: str, uname: str, pfile: list[str], dfile: list[str], dolist) -> tuple[str, str, list[str]]:
    """
    make or update the postfix and dovecot users files
    aname is A-label domain
    return (new dfile, new pfile, list of directories)
    """
    # list mailboxes
    def listusers(ulist):
        fs = "{:6s} {:10s} {:s}"
        print(fs.format("Mailbox","Password", "Mail address"))
        for u in ulist:
            print(fs.format(f"mailbox{u}", pwds[u], f"{addrs[u]}@{uname}"))
        print("")

    addrs = {}                          # address for mailboxN
    pwds = {}                           # passwords for mailboxN
    # read the addresses from the postfix file
    for l in pfile:
        if l[:1] in ("", "#"):  # blank or comment
            continue
        r = re.match(r'(.*)@(.*) mailboxes/mailbox(\d+)/Maildir/', l)
        if r:
            mbox = r.group(1)
            dom = r.group(2)
            userno = r.group(3)
            if dom in (aname, uname):
                if mbox != 'postmaster':    # postmaster aliased to first mailbox
                    addrs[int(userno)] = mbox
            else:
                print(f"Unknown domain, ignored {l.strip()}")
        else:
            print(f"Unknown line in password file, ignored {l.strip()}")
        
    
    # dovecot has the passwords
    for l in dfile:
        if l[:1] in ("", "#"):  # blank or comment
            continue
        r = re.match(r'mailbox(\d+):\{PLAIN\}(.+?)::::/home/' + mailuser + r'/mailboxes/mailbox(\d+)', l)
        if not r or r.group(1) != r.group(3):
            print("invalid entry in mailbox user file, ignored", l)
            continue
        pwds[int(r.group(1))] = r.group(2)
    
    # max user number so far
    if addrs:
        maxuser = max(addrs.keys())
        # list if there are already some
        if dolist:
            print("--- existing mailboxes ---")
            listusers(sorted(pwds.keys()))
    else:
        maxuser = 0


    # now add some users
    while True:
        if maxuser > 0:
            i = input("Do you want to add another mailbox? (n) ")
            if i[:1] not in ("Y", "y"):
                break

        u = input(f"Enter mailbox name for mailbox {maxuser+1}: ")
        if not u or any(x in u for x in " \t\r\n:@"):
            print("Name must be printing characters, no color or @ signs, try again")
            continue
        while True:
            p = input(f"Password for mailbox {maxuser+1}: ")
            if not p or any(z <=' ' or z>chr(127) or z==':' for z in p):
                print("Password must be ASCII printing characters and cannot contain colons, try again")
                continue
            break
        maxuser += 1
        addrs[maxuser] = u
        pwds[maxuser] = p

    # now create password files
    ulist = sorted(pwds.keys())
    # dovecot file
    dca = ""    # user numbers
    for u in ulist:
        passwd = pwds[u]
        dca += f"mailbox{u}:{{PLAIN}}{passwd}::::/home/{mailuser}/mailboxes/mailbox{u}\n"
        
    dfile = dca

    # postfix file
    pfa = ""
    pfu = ""
    didpm = False
    for u in ulist:
        mbox = addrs[u]
        pfa += f"{mbox}@{aname} mailboxes/mailbox{u}/Maildir/\n"
        pfu += f"{mbox}@{uname} mailboxes/mailbox{u}/Maildir/\n"
        if not didpm:   # first mailbox is also postmaster
            pfa += f"postmaster@{aname} mailboxes/mailbox{u}/Maildir/\n"
            pfu += f"postmaster@{uname} mailboxes/mailbox{u}/Maildir/\n"
            didpm = True
        
    pfile = f"{pfa}\n{pfu}"

    # list of maildirs
    maildirs = [ f"/home/{mailuser}/mailboxes/mailbox{u}/Maildir/" for u in ulist ]

    if dolist:
        listusers(ulist)
    return (pfile, dfile, maildirs)
        
if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description='Update mailbox accounts')
    parser.add_argument('-d', action='store_true', help="debug info");
    parser.add_argument('-l', action='store_true', help="list accounts when done");
    parser.add_argument('--user', type=str, help="user ID for mailboxes", default='mailuser');
    parser.add_argument('--pfile', type=str, help="postfix mailbox file", default='/etc/postfix/vmailbox');
    parser.add_argument('--dfile', type=str, help="dovecot user file", default='/etc/dovecot/users');
    parser.add_argument('--maildirs', type=str, help="maildirs to create")
    parser.add_argument('domain', type=str, help="Mail domain name");
    args = parser.parse_args();

    debug = args.d
    # read in existing files if they exist
    try:
        with open(args.pfile, "r") as f:
            pfile = [ l.strip() for l in f ]
    except FileNotFoundError:
        pfile = []
    try:
        with open(args.dfile, "r") as f:
            dfile = [ l.strip() for l in f ]
    except FileNotFoundError:
        dfile = []

    aname = args.domain
    uname = idna.decode(aname)

    (pout, dout, maildirs) = makeusers(aname, uname, pfile, dfile, args.l)

    with open(args.pfile, "w") as f:
        f.write(pout)
        if debug:
            print("wrote", args.pfile)

    with open(args.dfile, "w") as f:
        f.write(dout)
        if debug:
            print("wrote", args.dfile)

    if args.maildirs:
        with open(args.maildirs, "w") as f:
            for md in maildirs:
                print(md, file=f)
        if debug:
            print("wrote", args.maildirs)

