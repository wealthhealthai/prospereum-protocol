# Prospereum Website PR #1 — Remediation Re-review Brief

- Sprint: PR #1 review-only GAUNTLET, remediation round 1 (continuation; not a new sprint)
- Repository: `wealthhealthai/prospereum-website`
- PR/branch: PR #1, `site/rc1`
- Original reviewed base/head: `1d757905aab70b284620bdfe64592e76e1344b93` / `a17d37916543d336985bdcbd5f3a93cb558f630f`
- Re-review delta: `a17d37916543d336985bdcbd5f3a93cb558f630f..cf6cda193c0244d139935b8ca88a7ba27ec3a0ac`
- Final aggregate review boundary: `1d757905aab70b284620bdfe64592e76e1344b93..cf6cda193c0244d139935b8ca88a7ba27ec3a0ac`
- Requester/session: Fire (`1484343300201779340`) in `agent:kin:discord:channel:1560508042322255882`, following Jason's direct assignment of PR #1 review to Kin.
- Authority: read/review/test and write local review artifacts only. No product-code edits, commit/push to the website repository, GitHub review mutation, merge, deployment, Cloudflare change, or on-chain action.
- User-visible claim: a visitor starts on any of the six public pages, the page completes its pinned-block snapshot through an allowed RPC endpoint (including registered PartnerVault reads), navigation remains usable at desktop and mobile widths, and no unresolved placeholder text is shown.

## Objective

Determine whether the six-commit remediation delta resolves every confirmed finding from the original exact-SHA review without introducing correctness, security, release, or UI regressions. Produce an exact-SHA approval or request-changes verdict with full changed-file coverage and test receipts.

## Scope and review boundary

Review all 28 files changed in `a17d379..cf6cda1`, plus the minimum surrounding page, Worker, workflow, and deployment code needed to evaluate the fixes. Reuse the intact original full-PR coverage, then perform an aggregate integration pass at `cf6cda1`.

## Guardrails

- The Worker admits only page-required `(target, selector)` capabilities.
- Dynamic PartnerVault targets must be factory-registered at the same pinned block and fail closed when verification fails.
- Per-endpoint fallback commits only a complete, decodable snapshot.
- Request, calldata, Multicall, cache, timeout, origin, and rate-limit bounds fail closed.
- Upstream responses and errors must be structurally validated and sanitized before caching or returning.
- CI/deploy workflows must test the exact intended artifact without silently bypassing the gates.
- Public pages and navigation must remain usable in a real Chromium browser at desktop and mobile widths.

## Acceptance and verification

1. Every original finding has an evidence-backed disposition at `cf6cda1`; no unresolved blocker/required major or medium remains.
2. Every changed file is covered, and the aggregate base-to-head diff receives a cross-cutting security/integration pass.
3. From `site/pages`: `node --test token/test/token-logic.test.mjs partners/test/partners-logic.test.mjs shared/test/live-logic.test.mjs shared/test/rpc.test.mjs test/copy-drift.test.mjs test/site.test.mjs`.
4. From `site/worker`: `node --test test/*.test.mjs` and `npx --yes wrangler@3 deploy --dry-run --outdir /tmp/kin-pr1-worker-dry-run`.
5. Repository checks: `git diff --check a17d379..cf6cda1`; verify remote PR head remains `cf6cda1` and inspect PR CI evidence.
6. Real-browser local artifact check: serve `site/pages`, navigate through visible controls across all six pages at desktop and mobile widths, check hit targets/layout, and preserve screenshot/DOM evidence. Live Worker behavior remains unverified unless an exact-head Worker preview exists.

## Roster

- Accepted Prospereum roster (Jason, 2026-11-03): architect `anthropic/claude-opus-5-5` / native `claude-cli`; executor `anthropic/claude-opus-5-5` / native `claude-cli`; reviewer `openai/gpt-5.6-sol` / native `codex`, HIGH.
- This review-only continuation has no executor stage. Current parent evidence at intake: `openai/gpt-5.6-sol`, native Codex, ChatGPT OAuth, medium; parent performs adjudication and independent verification. Independent re-review must run as `openai/gpt-5.6-sol` via native Codex with effective HIGH and ChatGPT-backed OAuth; route/model/effort evidence is blocking.

## Out of scope

Website product-code changes, merge, deployment, Pages output-directory changes, Worker provisioning, Safe signer work, contract changes, and real-fund/on-chain actions.
