# Native whois for Haiku OS (x86_64)

A natively-compiled **whois 5.6.6** — the Debian "intelligent WHOIS client"
by Marco d'Itri — packaged as an installable Haiku `.hpkg` for **x86_64**.

- **Hand-built package:** `whois-5.6.6-1-x86_64.hpkg` (≈40 KB)
  - SHA256: `f756aa81d6fa4fd6d8750f18fc2f64b22f1612a54374058203add101905fed8d`
- **Recipe-built package:** `haikuports/packages/whois-5.6.6-1-x86_64.hpkg`
  (+ `whois_debuginfo-5.6.6-1-x86_64.hpkg`), produced by the official recipe
  under `haikuporter`
  - SHA256: `3b07beb0ad27e37e6a457c5b3c68a6a201ce1002fe0ff1e0aa9c86190ac8f3a1`
    (strict-policy `-S` build of 2026-10-14; embeds the configured
    `packager: Benjamin Pages<benjamin@t-pas.net>`)
- **Install:** `pkgman install whois-5.6.6-1-x86_64.hpkg`
- **After install:** `whois` → `/boot/system/bin/whois`, man pages under
  `/boot/system/documentation/man/`

---

## 1. What this is, and how this tool was chosen

The project ports classic Linux/BSD CLI tools to Haiku, one folder per tool
(see `../rsync`). Candidates are checked against the OS and the package
repositories before porting — several plausible ones turned out to exist:

| Candidate | Outcome |
|---|---|
| `ss` | Not needed — **Haiku ships a native `netstat`** (`src/bin/network/netstat`, fed by the private syscall `_kern_get_next_socket_stat()`) |
| `nslookup`, `dig` | Already packaged as **`bind_utils` 9.16.50-2** in official HaikuPorts. HaikuDepot's search never shows it for "dig"/"nslookup" because the depot matches package *name/description* only — the package is called `bind_utils` ("…DNS troubleshooting"). Search "dns", or `pkgman search dig` (matches the `cmd:dig` resolvable) |
| `socat`, `whois`, `ngrep`, `iftop`, `bmon`, `net-snmp`, `lsof` | Genuinely missing → **whois picked** (lsof infeasible: no `/proc`, no fd-enumeration API) |

### whois vs BSD whois — source comparison
| | Debian `rfc1036/whois` (chosen) | FreeBSD `usr.bin/whois` |
|---|---|---|
| Code | whois.c 42 KB + utils.c, plain GNU Makefile | single 15 KB file, no build system |
| Dependencies | libc only (libidn2/iconv/crypt auto-off) | libc; err.h/sysexits.h checks |
| Features | IANA→TLD→RIR→registrar referral chain, `whois.conf`, charset recoding | basic server guessing |
| License / activity | GPL-2.0-or-later, active (5.6.6, Feb 2026) | BSD, tracks FreeBSD |

Debian's whois is *the* Linux `whois`, builds essentially unmodified on
Haiku, and its referral logic was verified working end-to-end.

---

## 2. Target environment

- **OS:** Haiku R1~beta6, hrev59866, x86_64 (lab VM at `192.0.0.136`)
- **Toolchain (native on Haiku):** gcc 13.3.0, GNU make, perl (used at build
  time to generate the server tables and `version.h`), `package`, `haikuporter`
- **Source:** whois 5.6.6 — Debian-pool native tarball
  (`whois_5.6.6.tar.xz`, SHA256 `121a3b04…` cross-checked against Debian's
  PGP-signed `.dsc`), `SOURCE_DIR="work"`

Everything is built **on the Haiku machine itself** — no cross-compilation.

---

## 3. Haiku-specific changes

One patchset, two hunks: `src/whois-5.6.6.patchset`
(`git format-patch` form; applies with `git am -3` or `patch -p1`).

### 3.1 Platform feature macros (`config.h`)

Upstream detects platforms with `#ifdef __GLIBC__ / __FreeBSD__ / __APPLE__ …`
cases — there is **no `__HAIKU__` case**, so by default none of the feature
macros fire. The patch adds:

```diff
+#ifdef __HAIKU__
+# define HAVE_GETOPT_LONG
+# define HAVE_GETADDRINFO
+# define HAVE_REGEXEC
+#endif
```

Without it the build still *succeeds* — but long options silently break
(negative-tested: `./whois: invalid option -- '-'` on `--version`), and
referral regex matching is compiled out. Haiku's libroot provides all three
functions.

### 3.2 Socket linkage (`Makefile`)

```diff
+# Haiku: the socket API lives in libnetwork, not libroot
+whois_LDADD += -lnetwork
```

Same class of fix as the rsync port (`socket`, `connect`, `gethostbyname`,
`getservbyname` … are in `libnetwork.so`).

### 3.3 Man-page relocation (build script + recipe, not a source patch)

Upstream's `install-whois` target writes to `share/man`, but **Haiku's
`man` (mandoc) only reads `/boot/system/documentation/man`** — pages shipped
in `share/man` are invisible (`man whois` → "No entry"). Both the hand script
and the recipe therefore re-root the pages after installation. Haiku's system
dirs are read-only packagefs mounts, so packages are the only way pages get
there — which is why the relocation matters.

> Note: this affected the rsync port too — its hand-built package shipped
> `share/man` pages, so `man rsync` failed. (Its recipe path was always
> correct: `runConfigure` passes `--mandir=$manDir` automatically.) Fixed
> 2026-10-14: rsync's hand script now re-roots the pages the same way and
> its package was rebuilt.

---

## 4. Features enabled / disabled

| Area | This build |
|---|---|
| Server selection | Full: IANA bootstrap, TLD list, RIR referral recursion, registrar hop |
| Local overrides | ✔ `CONFIG_FILE=/boot/system/settings/network/whois.conf` (whois.conf(5)); missing file → graceful fallback (`ENOENT`) |
| Long options | ✔ `--version`, `--host`, `--port`, … |
| IDN (libidn2) | ✘ not present on Haiku — auto-detected off by upstream Makefile |
| Charset recoding (iconv) | ✘ off (upstream default off; only Debian enables it) |
| NLS/gettext | ✘ off (upstream only enables on glibc/BSD/macOS) |
| `mkpasswd` helper | ✘ not built — needs libcrypt; out of scope |

---

## 5. Build process

### Hand-scripted (proves the goal, like rsync's `build_haiku_rsync.sh`)

```sh
# on the VM, source dir holds the tarball + patchset:
/boot/home/build_haiku_whois.sh
# extract → patch -p1 → make whois → stage (man re-root) → package create
# → /boot/home/out/whois-5.6.6-1-x86_64.hpkg
```

Essential steps (what the script does):

```sh
tar -xf whois_5.6.6.tar.xz          # top-level dir: work/
cd work && patch -p1 < ../whois-5.6.6.patchset
make whois CONFIG_FILE=/boot/system/settings/network/whois.conf
make install-whois prefix=/boot/system DESTDIR=/tmp/destroot
# re-root man pages share/man → documentation/man, strip, package create
```

Only the `whois` target is built — `make all` would also build `mkpasswd`
(libcrypt) and the gettext `.mo` catalogues.

### Via the recipe (primary path)

```sh
cd /boot/home/haikuports
haikuporter --lint whois        # policy check
haikuporter -y whois            # chroot build → packages/*.hpkg
haikuporter -y --test whois     # build + TEST()
```

No autotools involved (plain GNU Makefile), so the recipe just calls `make`
directly; `cmd:perl` is a `BUILD_PREREQUIRES` because the server tables and
`version.h` are generated by perl scripts from `debian/changelog`.

---

## 6. Packaging

Key `.PackageInfo` fields (hand-built package):

```
name            whois
version         5.6.6-1
architecture    x86_64
summary         "Intelligent WHOIS client"
licenses { "GNU GPL v2" }
provides {
    whois = 5.6.6-1 compat >= 1
    cmd:whois = 5.6.6-1
}
requires {
    haiku >= r1~beta5
}
```

- The only real dependency is `haiku` itself (libroot + libnetwork).
- `package create` accepted `"GNU GPL v2"` as a recognized license identifier
  (the rsync port needed `"GNU GPL v3"` — same rule, v2 variant works).
- Package file paths are relative to `/boot/system`.

---

## 7. Verification (all performed on the lab VM)

**Install & basics**
- `pkgman install` (hand-built *and* recipe-built packages) ✔
- `whois` → `/boot/system/bin/whois`, `whois --version` → `Version 5.6.6.` ✔
- Long options work — and *fail* without the patch (negative test) ✔

**Real-world queries (network from the VM)**
- `whois haiku-os.org` → registry record, then registrar hop to Namecheap ✔
- `whois example.co.uk` → TLD referral to Nominet (`whois.nic.uk`) ✔
- `whois -h whois.arin.net 8.8.8.8` → ARIN record ✔
- `whois 1.1.1.1` → automatic IP→RIR guess, served by `whois.apnic.net` ✔

**whois.conf (local override)**
- conf absent → normal operation (ENOENT handled) ✔
- conf present (`haiku-os.org bogus.invalid`) → query redirected:
  `getaddrinfo(bogus.invalid): No address associated with hostname` ✔
- conf removed → normal operation again ✔

**Man pages**
- `man whois`, `man whois.conf` render from
  `/boot/system/documentation/man` ✔ (with mandoc's benign
  "outdated mandoc.db … run makewhatis" warning — `man dig` prints the same
  one; environmental, not a packaging defect)

**Toolchain validation**
- `haikuporter --lint whois` → clean
- `haikuporter -y whois` → exit 0, correct hpkg + debuginfo split
- `haikuporter -y --test whois` → exit 0 (TEST phase: offline
  `--version`/`--help` checks)
- `haikuporter -y -S whois` (strict policy, submission gate) → **exit 0,
  zero warnings** (2026-10-14)

---

## 8. Repo layout

```
whois/
├── whois-5.6.6-1-x86_64.hpkg     # hand-built deliverable
├── src/
│   ├── whois_5.6.6.tar.xz        # upstream source (checksum = signed .dsc)
│   └── whois-5.6.6.patchset      # Haiku patches (format-patch mailbox)
├── haikuports/
│   ├── FormatVersions            # RecipeFormatVersion=1
│   ├── net-misc/whois/
│   │   ├── whois-5.6.6.recipe
│   │   └── patches/whois-5.6.6.patchset
│   └── packages/                 # haikuporter outputs (+ debuginfo)
├── build_haiku_whois.sh          # hand build + package script
└── README.md                     # this document
```

---

## 9. Reproducing from scratch

1. Copy `src/whois_5.6.6.tar.xz` + `src/whois-5.6.6.patchset` to the VM
   (`/boot/home/build/whois-src/`).
2. Run `build_haiku_whois.sh` → hpkg in `/boot/home/out/`.
   No extra packages needed (gcc/make/perl ship with the base toolchain).
3. Recipe path: place the recipe + patchset in a haikuports tree (with
   `FormatVersions`), then `haikuporter -y whois`.

---

## 10. Gotchas worth remembering

- **`PATCHES=` files must be `git format-patch` mailboxes** — haikuporter
  applies them with `git am -3`; a plain `git diff` output fails with
  *"Patch format detection failed"* (`git am` exit 128).
- **`SOURCE_DIR="work"`** — the native Debian tarball's top-level directory
  is `work/`.
- **`share/man` ≠ Haiku's man tree** — use `/boot/system/documentation/man`
  (the recipe re-roots automatically).
- Re-installing the same version with pkgman needs
  `pkgman uninstall -y whois` first (otherwise it's a no-op).
- Upstream `whois.conf(5)` documents a compiled-in path; this build sets it
  to `/boot/system/settings/network/whois.conf` (the VM's settings dir is
  user-writable; on a stock system it is managed like `resolv.conf`).

---

## 11. Scope notes

- **x86_64 only** — recipe declares `ARCHITECTURES="all !x86_gcc2"` but no
  `SECONDARY_ARCHITECTURES` (unlike rsync); only x86_64 was built/tested.
- `mkpasswd`, iconv recoding, and NLS are out of scope (see §4).

---

## 12. Upstream submission status

Everything that can be validated locally has been validated:

| Gate | Status |
|------|--------|
| No upstream conflicts | ✔ full haikuports tree scan found **zero** whois-related paths (recipe is new upstream) |
| `haikuporter --lint whois` | ✔ clean |
| `haikuporter -y -S whois` (strict policy) | ✔ **exit 0, zero warnings** (2026-10-14) |
| PACKAGER identity configured | ✔ real identity set in `~/config/settings/haikuports.conf` and embedded in the `-S`-built package (`packager: Benjamin Pages<benjamin@t-pas.net>`, re-verified 2026-10-14) |

The recipe is **submission-ready as-is** — no manual steps remain.

Submission steps:

1. Fork `github.com/haikuports/haikuports`.
2. Copy `haikuports/net-misc/whois/` (recipe + `patches/`) into the fork.
3. Open a pull request (recipe-only; the tarball checksum is verified
   against Debian's PGP-signed `.dsc`).

Optional upstreaming: the two patch hunks (the `__HAIKU__` case in
`config.h` and `-lnetwork` in the Makefile) could be proposed to upstream
(github.com/rfc1036/whois, Marco d'Itri) — if accepted, the patchset
shrinks to what the build recipe handles (man-page relocation).
