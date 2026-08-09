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
