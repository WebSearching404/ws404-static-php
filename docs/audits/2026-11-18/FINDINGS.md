# Static PHP build and distribution audit

<!--
provenance:
  origin: external-chatgpt-repo-audit
  skill: audit-repository
  tool: Codex (OpenAI)
  date: 2026-11-18
  pinned_commit: 83260d0d47cf31fcbe0fbe139f77d9458f7311af
  repo: WebSearching404/ws404-static-php
-->
> **Provenance:** External ChatGPT/Codex `$audit-repository` audit (not in-repo maintainer work).
> **Date ran:** `2026-11-18` · **Pinned commit:** `83260d0d47cf31fcbe0fbe139f77d9458f7311af` · **Repo:** `WebSearching404/ws404-static-php`

All five archives in the two current release lines matched their published SHA-256 digests and the corresponding consumer pins. Each contained one executable Linux x86-64 ELF with no interpreter segment. The three PHP binaries reported **8.1.34, 8.3.36 and 8.4.27** in offline execution. The existing releases serve the observed consumer contract. The default settings for the next build omit one of those versions.

The public review confirmed **eight findings, two Medium and six Low**. There are zero open candidates or disproved items in the public manifest. The two Medium items affect future releases. Neither establishes a mislabeled or missing archive in the current releases.

## Scope and evidence

The audit resolved public `main` and remote HEAD to the requested commit above on November 18, 2026 (Mountain time). A fresh detached checkout contained five ordinary tracked files, with clean tracked, untracked and ignored status before and after testing. It had no submodules, LFS pointers, native tests, dependency manifests or repository-specific PR template. The documentation publication base was the same commit. All eleven earlier PRs were merged. The release history covers PHP v1.0.0, v1.1.0, v1.2.0 and the separate tools-v1 line.

| Flow | Priority | Evidence and result | Coverage |
| --- | --- | --- | --- |
| Dispatch → build → publish | High | Traced both full workflows. A manual dispatch builds. A successful build and a nonempty release tag enable the matching publisher. A PR or push to main runs the read-only lint workflow. The protected branch requires `actionlint`. | Complete source trace. No dispatch or publication exercised. |
| Assets → consumer | High | Read release metadata, hashed all five current tarballs, checked member name/type/mode and parsed the ELF program headers. Compared each digest with the consumer's pinned digest at its resolved revision. Observed all three exact PHP patch levels in a completed consumer CI job. | Complete for these five archives and that job. Resident tool caches, unrelated jobs and individual installation states are unknown. |
| PHP, extensions and proof programs | High | Current build run completed all three matrix jobs and publication. A sampled build log identified static-php-cli 2.8.5 and the expected PHPStan diagnostic. Each published binary returned true for pcntl and mbregex in a credential-free, offline Linux container. | Complete for the three published executables under these probes. No fresh PHP compilation, dependency install or replay of every historic build. |
| Static tools | Medium | Checked the rsync 3.5.0 source digest against the upstream release API and the Info-ZIP 3.0 digest against the Ubuntu source description. Current archives reported those versions locally. The tools release run passed the static and copy/exclude/archive checks. | Complete for current release identity and sampled behavior. No live runner provisioning. |
| Release reproducibility and recovery | High | Compared tag commits with release-run SHAs for v1.2.0 and tools-v1. Both matched. Reviewed retry behavior, existing tags, artifact selection and metadata. Replayed both packaging steps with identical program bytes. | Partial. Floating build sources, compiler/image updates and external package resolution prevent a claim of bit-for-bit source rebuilds. |
| CI and prior fixes | Medium | All three workflows passed actionlint 1.7.12 with ShellCheck 0.11.0. Both Linux linter archive digests matched their official releases. Reviewed [the PHP 8.3 build fix](https://github.com/WebSearching404/ws404-static-php/pull/5), [lint pins](https://github.com/WebSearching404/ws404-static-php/pull/7), [tools build](https://github.com/WebSearching404/ws404-static-php/pull/8), [static linking](https://github.com/WebSearching404/ws404-static-php/pull/9), [ldd handling](https://github.com/WebSearching404/ws404-static-php/pull/10) and [tools release selection](https://github.com/WebSearching404/ws404-static-php/pull/11). | Complete for the five-file tree and those earlier controls. No application server, persistent application data, database or WordPress integration to exercise. |

The GitHub connector identified the release jobs and their steps. Repository-scoped GitHub APIs supplied tag, archive, workflow and branch-protection evidence beyond identity. An authorized consumer source and CI-log read corroborated the release contract. Public evidence below omits private consumer particulars. The available website connectors and hosting aliases serve a different environment. No runner-host inventory was necessary to establish what the sampled CI job actually executed. No live upload, tag operation or fleet change was part of verification.

The API's latest PHP patch per published minor matched the binaries at observation time. PHP 8.1 is the intentionally retained, upstream end-of-life compatibility floor. Upstream also supports 8.2 and 8.5. The consumer selects 8.1, 8.3 or 8.4, so upstream branch support alone does not add a product requirement. Upstream rsync lists 3.5.2. The existing tool's 3.5.0 source digest and the distributed tool's version agree. A future source refresh will need the local copy/exclude smoke and a separate release decision. [PHP support policy](https://www.php.net/supported-versions.php) · [PHP release index](https://www.php.net/releases/) · [rsync releases](https://github.com/RsyncProject/rsync/releases)

## Findings

Each entry is **confirmed, high confidence** at the pinned source. Priority follows the impact on a future build or consumer update.

### SP-01 · Medium · Release tags can name a different revision from the build

Both publish steps call `gh release create` without a target. The CLI creates an absent tag at the current default branch and uses an existing tag's target. A build dispatched from another ref, or one that straddles a main-branch update, can therefore ship the right bytes under the wrong source tag. Digest verification authenticates the archive bytes but cannot establish that the source link identifies their recipe. The two sampled release tags matched their successful build runs.

**Change and verification.** Bind new release tags to the immutable dispatch SHA and reject a pre-existing tag that resolves elsewhere. Exercise absent, matching lightweight, matching annotated, mismatched and unreadable tag states for both publishers without contacting a release service. Preserve both archive namespaces, existing correctly targeted tags and the tools line's latest setting. Evidence is the full publish steps and the CLI's documented contract. [PHP workflow, lines 380–384](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build.yml#L380-L384) · [Tools workflow, lines 240–245](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build-tools.yml#L240-L245) · [GitHub CLI manual](https://cli.github.com/manual/gh_release_create)

### SP-02 · Medium · The default PHP matrix omits a distributed minor

Both v1.1.0 and v1.2.0 carry PHP 8.3. A consumer selects this minor by its own archive name and digest. The default dispatch still expands to 8.1 and 8.4 only. A maintainer who supplies just a new release tag gets a successful release without an 8.3 asset to repin. Existing pinned downloads continue to work. The current release run explicitly built all three.

**Change and verification.** Include 8.3 in the default and document the three-version release recipe. Verify the default JSON resolves to the current release minors and a caller-selected single minor still reaches the matrix unchanged. Default builds gain one parallel compilation. Keep explicit subset builds available. Evidence is the input, matrix, current archives and consumer selectors. [PHP workflow, lines 28–41](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build.yml#L28-L41) · [v1.2.0](https://github.com/WebSearching404/ws404-static-php/releases/tag/v1.2.0)

### SP-03 · Low · Consumer maintenance instructions describe a retired pin inventory

README §7 sends maintainers to a table of independent cross-repository pins and says that duplication is permanent. The current consumer centralizes its PHP release pins, discovers local pins, and searches for stray copies. It selects published PHP releases by asset shape. Following the earlier instructions directs a maintainer to the wrong place to perform or investigate a repin.

**Change and verification.** Point readers at the current consumer action and drift script. Describe the tag, per-archive digest, and exact patch record without restating a private inventory. Check the wording against the owning selector, install path and drift logic. Preserve the external artifact and notes formats. Evidence is a comparison of both complete source paths with the prior documentation decision. [README §7](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/README.md#7-staying-current-and-how-youd-know-if-it-wasnt) · [Prior documentation change](https://github.com/WebSearching404/ws404-static-php/pull/6)

### SP-04 · Low · PHP verification misses configured capabilities

The build requests pcntl and mbregex, but the module list omits pcntl and no assertion calls the mbregex API. mbregex is a feature of mbstring, so looking for a module named mbregex would be incorrect. The workflow also runs `php -m` once per requirement through an early-exiting reader under pipefail. Depending on write timing, a valid producer can report a broken pipe after a match. Current archives provide both capabilities.

**Change and verification.** Capture the version and module list to completion, check pcntl and assert `function_exists('mb_ereg')`. Test a complete binary, an absent module, an absent function, a producer error and a wrong minor. The gate should reject only builds that fail their stated contract. Evidence is source plus the three released-binary capability probes. [PHP build configuration](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build.yml#L65-L69) · [Version and module step](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build.yml#L227-L248)

### SP-05 · Low · A failed ELF inspection can be reported as a passing check

Both build jobs test for an interpreter using `readelf` inside the condition of a shell pipeline. An inspection error follows the same false branch as a successful scan without an interpreter. In the original PHP step, substituting an inspector that returned 2 yielded exit 0 and the self-contained message. The tools step has an additional ldd check, which does not validate that the ELF inspection succeeded. All five published assets passed independent header parsing.

**Change and verification.** Require a successful inspector exit before reading its full result. Test successful static output, a real interpreter header and an inspector error on both build paths. Keep tools' separate ldd and functional checks. Compatibility impact is limited to previously inconclusive inspections. [PHP verification](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build.yml#L207-L225) · [Tools verification](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build-tools.yml#L144-L172)

### SP-06 · Low · Identical binaries can yield different distribution digests

Both package steps copy file timestamps and archive ownership into their tarballs. The PHP step first installs a fresh copy, which stamps it with the current time. Replaying the original steps with identical executable bytes and different timestamps produced different archive bytes for both release lines. Consumers pin the compressed archive, so a packaging-only change forces new pins and obstructs comparison of independent builds.

**Change and verification.** Normalize the tar metadata and gzip header in both packaging paths. Compare byte-identical archives from inputs with different times and verify the exact member name, mode and content on extraction. Changed program bytes must still alter the digest. This is packaging reproducibility for equal binaries. The compiler, build dependencies and their independent reproducibility remain separate considerations. The next newly produced archive will require its own pin. [PHP packaging](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build.yml#L296-L319) · [Tools packaging](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build-tools.yml#L186-L199)

### SP-07 · Low · The PHP recipe resolves third-party action tags at run time

Four action uses in the PHP workflow select a moving v4 tag. The same source commit can therefore invoke different implementations on a later build. The tools and lint workflows already use reviewed full action SHAs. Independent pins on the final assets protect consumers when installing a released archive.

**Change and verification.** Resolve the same action majors to their current upstream commits, use exact SHAs with release comments, and check each value against its owning repository. Preserve action inputs, permissions and dispatch behavior. Future action updates become explicit diffs. Evidence is the workflow and upstream tag resolution. [PHP workflow](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build.yml)

### SP-08 · Low · Version banners can stop a successful tools build

The tools workflow pipes the compiler, zip and rsync version banners to `head` under `pipefail`. A reader can exit after the requested lines while a healthy program still has output to write. In an offline Linux container, the exact banner pipelines returned producer status 141 and reader status 0 in **30 of 30 trials for each** of the two tools-v1 executables. During a fresh source build, linking zip succeeded but the step stopped at the banner before staging its binary. Earlier hosted releases passed, so this failure depends on pipe timing. The compiler variant was verified with a verbose fixture. A failure from the real compiler's version command was not observed.

**Change and verification.** Read each banner to completion while printing only its first one or two lines. Exercise the actual install, zip-build and rsync-build steps with a verbose successful tool and a tool that returns a nonzero status. Check that the expected status propagates and log size stays bounded. Build flags, packaged program bytes and release selection are unaffected. Evidence is source and local runtime. [Tools workflow, lines 68–73](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build-tools.yml#L68-L73) · [Zip and rsync steps](https://github.com/WebSearching404/ws404-static-php/blob/83260d0d47cf31fcbe0fbe139f77d9458f7311af/.github/workflows/build-tools.yml#L106-L139)

## Verification boundaries and review order

Start with the release target and the default matrix. The remaining changes can be reviewed independently. The two distribution lines have separate tags and the current tools publisher preserves its explicit latest setting. Existing archives require no replacement.

The pinned-tree lint command was `actionlint .github/workflows/build.yml .github/workflows/build-tools.yml .github/workflows/ci.yml` with ShellCheck available, exit 0. In disposable unprivileged containers with networking disabled, the audit ran the archived executables and replayed selected shell steps with synthetic inputs. Release assets were read by tag, compared to release API digests, then inspected with Python's tar and ELF readers before execution. Scratch fixtures stayed outside the clean checkout. A complete historical compiler image, source lock for every transitive build input, and a second independently rebuilt PHP binary set were unavailable. No performance benchmark or production-wide compatibility claim follows from these checks. The existing manual build gate keeps expensive compilation off ordinary PRs. [PHP build run](https://github.com/WebSearching404/ws404-static-php/actions/runs/40986112385) · [Tools build run](https://github.com/WebSearching404/ws404-static-php/actions/runs/31759413321) · [PHP release](https://github.com/WebSearching404/ws404-static-php/releases/tag/v1.2.0) · [Tools release](https://github.com/WebSearching404/ws404-static-php/releases/tag/tools-v1)
