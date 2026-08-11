# ws404-static-php

Statically linked PHP CLI builds for `linux-x86_64`, built by this repo's own CI and published
as GitHub release assets.

Consumed by the WebSearching404 fleet's self-hosted CI runner. Nothing here is WordPress- or
fleet-specific — it is a stock PHP interpreter — but the *extension set* is derived from the
fleet's needs, so read §3 before reusing it elsewhere.

---

## 1. Why this exists

The NAS runner (`nas-linux-1`) is deliberately hostile territory for a normal PHP install:

- **No root.** The container runs as uid 1001 with `no_new_privileges=1`; `sudo` exists but can
  never elevate. `shivammathur/setup-php` needs the Ondrej PPA *and* root, so it cannot work
  there — this is a structural blocker, not a configuration gap.
- **Default-deny egress.** All traffic goes through a proxy with an allowlist. A request to a
  non-allowlisted host does **not** error — it **hangs** until the job times out. One blocked
  host once burned a full 10-minute timeout before anyone realised why.

Upstream `static-php-cli` already publishes exactly the binary we want, but it is served from
`dl.static-php.dev`, which redirects twice and terminates at a DigitalOcean Spaces bucket:

```
dl.static-php.dev/...            302
  -> dl.static-php.dev/down?path=...        302
  -> static-php-cli.fra1.digitaloceanspaces.com/...   200
```

None of those hosts is allowlisted, and the binary is **not** published as a GitHub release
asset by either `crazywhalecc/static-php-cli` or `static-php/hosted` — verified by enumerating
all 2,409 release assets across both repos, of which zero are a PHP runtime.

Allowlisting a third-party blob host so the runner can pull an unsigned binary onto hardware
inside a private LAN is precisely what `PHPSTAN_TURBO: "0"` was set fleet-wide to prevent.

**So we build it ourselves.** The asymmetry is the whole trick: the *build* runs on a
GitHub-hosted runner with unrestricted egress and can fetch whatever it needs, while the *NAS*
runner only ever sees the finished artifact on `github.com` — already allowlisted, no new
hosts, no new credentials.

## 2. The integrity model, and why "just checksum it" isn't enough

GitHub publishes each release asset's digest through the API, **served by a different endpoint
than the bytes**:

```bash
gh api repos/WebSearching404/ws404-static-php/releases/tags/<tag> --jq '.assets[]|{name,digest}'
```

That separation is the entire point. Hashing a file you just downloaded from a single source
pins *"what I happened to receive"*, not *"what the publisher published"* — it is
trust-on-first-use wearing a checksum's clothing. Fetching the expected digest from a different
endpoint than the artifact is what makes it an anchor.

This mirrors the existing `.rosetta-corpus.pin` pattern in `mikrotik-mcp-hardened`, which takes
its digest from the release API and refuses to install on mismatch. Consumers here should do
the same: **fail closed**.

## 3. The extension set, and how it was derived

A static PHP **cannot `dlopen`**. Anything not compiled in is unavailable forever — no
`extension=` line, no `-d`, no recovery. So the set is derived from the fleet's *committed*
`composer.lock` files rather than guessed:

| source | extensions |
|---|---|
| `phpunit/phpunit` 10.5 | `dom` `filter` `json` `libxml` `mbstring` `xmlwriter` |
| `phpunit/php-code-coverage` | `dom` `libxml` `xmlwriter` (hard require even with `coverage: none`) |
| `nikic/php-parser` | `tokenizer` `json` |
| `theseer/tokenizer` | `xmlwriter` `dom` `tokenizer` |
| `phar-io/manifest` | `phar` `dom` `xmlwriter` |

### The two that appear in no lockfile and are still mandatory

This is the trap, and it is why a "minimal" build fails in a way that looks like something else:

1. **`phar`** — `phpstan/phpstan` declares only `{"php": "^7.4|^8.0"}` and no `ext-*`, so a
   PHPStan-only repo's lockfile lists **zero** extensions. But its `bin/phpstan` is a stub:

   ```php
   Phar::loadPhar(__DIR__ . '/phpstan.phar', 'phpstan.phar');
   require 'phar://phpstan.phar/bin/phpstan';
   ```

   `composer.phar` is a phar too. Without `phar` the install succeeds cleanly and the **first**
   invocation dies.

2. **`openssl`** — composer lists it only under `suggest`. But `repo.packagist.org` is
   HTTPS-only, so with no openssl the `https://` stream wrapper does not exist and metadata
   resolution fails. Treat it as required.

`zip` is included rather than relying on composer's `unzip`/`7z` fallback: the lanes run
`--prefer-dist`, and whether `unzip` exists in the runner image is not something CI should
depend on.

Deliberately **excluded** after checking the fleet actually doesn't use them: `intl` beyond the
default, `gd`, `pdo_mysql`, `mysqli`. WordPress itself never boots in these lanes.

## 4. Verification — what the build proves before it publishes

Every check can fail, and several are negative assertions. A build that cannot run the real
toolchain does not ship.

- **Genuinely self-contained** — asserts there is **no `PT_INTERP`** program header. This is the
  decisive test, not `file` output: a static-PIE binary reports as *"dynamically linked"* while
  being perfectly self-contained. No interpreter means no dynamic loader, which is what lets it
  run rootless with no matching shared libraries present.
- **Version matches** what was requested.
- **Every required module present**, checked one at a time. `spc build` can succeed while
  silently omitting an extension; that failure would otherwise surface weeks later in an
  unrelated repo's CI.
- **composer runs** — exercises `phar`, `openssl` and `zip` together, fetched from
  `github.com/composer/composer/releases` (not `getcomposer.org`, which the runner cannot
  reach), so the build is honest about what the consuming lanes can actually do.
- **PHPStan actually analyses** — installs PHPStan and runs it against a file with a *seeded*
  type error. The job **fails if PHPStan exits 0**, because an analyser that silently no-ops
  looks identical to one that passes.

## 5. Building

Actions → *Build static PHP* → *Run workflow*.

| input | meaning |
|---|---|
| `php-versions` | JSON array, default `["8.1","8.4"]` |
| `release-tag` | **Leave empty to build and verify without publishing.** Set it to publish. |
| `spc-ref` | `static-php-cli` release to build with; empty = latest |

`8.1` is not optional: it is the default `php-version` of the fleet's reusable `phpstan.yml`,
and the plugin headers declare `Requires PHP: 8.1`. `8.4` covers the forward-compat lint.

Note that PHP 8.1 is past upstream security support. That is acceptable *here* — this binary
runs CI analysis on private runners and never serves traffic — but it is a reason to keep the
floor moving, not to ignore.

## 6. Consuming it

Fetch by pinned digest, verify, cache by digest, fail closed on mismatch. Stage it **outside**
the runner's `_work` directory so a `clean: true` checkout cannot clobber it.

Workflow steps then just put it on `PATH`; nothing needs root and nothing new is allowlisted.

## 7. Staying current, and how you'd know if it wasn't

A pin nobody can see is behind is **worse** than no pin: it looks deliberate while quietly
freezing, and PHP ships security releases. So the pin is paired with a detector.

`ws404-plugin-workflow`'s **`bin/check-static-php-drift.sh`** holds the logic;
`static-php-drift.yml` is only the monthly schedule and the issue plumbing around it. It checks
two independent things — whether each pin is behind the newest release here, and whether that
release's PHP patch level still matches upstream per branch (`php.net/releases/?json&version=`),
once per distinct tag. It **reports and never fails**: being behind is a reason to schedule a
rebuild, not to break every PHPStan and PHPUnit lane in the fleet. The signal is a GitHub issue
it opens, updates and closes on its own.

**The pin has more than one home, so the check covers a set of locations.** Today those are
`ws404-plugin-workflow`'s `phpstan.yml` and `ws404-shared-mcp`'s `phpunit.yml`, and each is
reported *separately*. The duplication is deliberate and not removable: shared-mcp's
`phpunit.yml` is self-contained by design (audit F-07) and the reusable `phpstan.yml` is
PHPStan-shaped, so there is no setup step to share. The predecessor grepped only its own
`phpstan.yml`, which made the shared-mcp copy invisible — a BEHIND issue would have been closed
by repinning `phpstan.yml` alone while a PHPUnit lane stayed on a stale PHP patch, with nothing
saying so. Locations in *other* repos are listed explicitly (without a token there is no way to
find them); workflows in the checker's own repo are globbed, so a self-contained lane added
there is covered the day it lands.

Three things that check gets right on purpose, all learned the hard way:

- **Its own pin comes from the checkout; every other pin comes from the API.** The file is
  already on disk at the ref the job is running from, so no token can take it away. That is a
  regression guard, not an optimisation: an earlier cut read every location over a repo-read
  PAT, and that PAT cannot read even its own repo, so a location that had never needed a token
  started reporting UNKNOWN. Cross-repo pins have no checkout — and `ws404-shared-mcp` is
  private, so without a suitable PAT it reports **UNKNOWN** rather than being skipped.
- **Three-way, never two.** Every location's result is BEHIND / CURRENT / **UNKNOWN**, and
  UNKNOWN is never folded into "fine". A repo the token cannot read, an unreachable php.net or
  releases API, a release with no `PHP-BUILT` block, or a pin whose format changed all mean *we
  do not know* — and printing "current" there would be a false all-clear on the exact mechanism
  being policed.
- **`sort -V`, never plain `sort`.** Lexically `8.4.9` sorts *above* `8.4.24`. The
  `php/php-src` tags API also returns tags in non-version order, which makes this easy to walk
  into.

None of that is left to inspection. `tests/test-static-php-drift.sh` runs the real script byte
for byte with only `gh` and `curl` shimmed, and Meta CI gates it. Every negative case asserts
the *absence* of the all-clear line rather than merely the presence of UNKNOWN, and the tests
pin the location set itself — drop the shared-mcp entry and they go red. The predecessor lived
inline in the workflow and could not be tested at all, which is why the logic moved.

That comparison needs the exact patch level, which the asset name does not carry
(`php-8.1-...` is the minor). So the release notes include a machine-readable block, derived by
**running** the packaged artifact rather than echoing a build-time variable — it describes what
actually shipped:

```
PHP-BUILT 8.1 8.1.34
PHP-BUILT 8.4 8.4.24
```

## 8. CI in this repo

Deliberately small: `actionlint` (which also runs shellcheck over every `run:` block) on each
push and PR, and it is the one required check on `main`.

There is **no build-on-every-PR**, on purpose. A full build is ~17 minutes per PHP version and
throws the binary away, while `build.yml` already verifies itself far more strictly than a smoke
test would — see §4. It is dispatch-only, so a break surfaces on the next deliberate build with
a human watching. Paying 17 minutes on every README typo to shorten that loop is a bad trade;
what actually breaks a repo shaped like this is a shell mistake, and actionlint catches that in
seconds.
