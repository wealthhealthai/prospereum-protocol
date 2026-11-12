# Prospereum Website PR #1 — Round 2 Focused Re-review Brief

- Lane: GAUNTLET remediation re-review, fix iteration 2
- Repository/PR: `wealthhealthai/prospereum-website` PR #1, `site/rc1`
- Prior reviewed head: `cf6cda193c0244d139935b8ca88a7ba27ec3a0ac`
- Exact candidate head: `58d8a6e4c166f98167828ee46d8252e3ee5c4ff1`
- Focused delta: `cf6cda193c0244d139935b8ca88a7ba27ec3a0ac..58d8a6e4c166f98167828ee46d8252e3ee5c4ff1`
- Aggregate boundary: `1d757905aab70b284620bdfe64592e76e1344b93..58d8a6e4c166f98167828ee46d8252e3ee5c4ff1`
- Changed files: 26
- Authority: read/review/test plus local review artifacts only. No website code edits, GitHub review/comment writes, commits/pushes to the website repo, merge, deploy, Cloudflare mutation, or on-chain action.
- Roster: existing Prospereum sprint roster; independent reviewer `openai/gpt-5.6-sol`, native Codex, effective HIGH, ChatGPT OAuth. No executor stage in this review-only continuation.

## Objective

Verify that the four-commit delta resolves all nine round-2 findings without regression, with focused coverage of the changed code and affected security/integration paths, plus an aggregate pass at the exact candidate head.

## Required checks

1. Account for all 26 changed files.
2. Re-test each round-2 finding: block-keyed vault verdicts; ABI-decodable page snapshots; exact-head local preview; placeholders; exact calldata lengths; origin-required POST; JSON-RPC request/upstream/browser envelope correlation; byte-counted body limits; response-body timeout.
3. Specifically assess the parent probes showing: (a) Worker `validateRequest({jsonrpc:"2.0", method:"eth_chainId", params:{}})` remains accepted because non-array params become `[]`; (b) `pages/shared/rpc.mjs` accepts a response with `jsonrpc:"1.0"` and a mismatched ID.
4. Run Pages tests, Worker tests, both preview-gate modes, Wrangler dry-run, and diff checks. No deployment.
5. Findings only, never fixes. Number each finding with severity, file:line, defect, and concrete failure scenario. Zero findings must be explicit. Truncation or missing coverage is incomplete, never approval.

## Verification commands

- Pages: `node --test token/test/token-logic.test.mjs partners/test/partners-logic.test.mjs shared/test/live-logic.test.mjs shared/test/rpc.test.mjs test/copy-drift.test.mjs test/site.test.mjs`
- Worker: `node --test test/*.test.mjs`
- Preview shim: `node scripts/preview-gate.mjs --worker shim`
- Preview workerd: `node scripts/preview-gate.mjs --worker wrangler --wrangler-timeout-ms 240000`
- Dry-run: `npx --yes wrangler@3 deploy --dry-run --outdir /tmp/kin-pr1-worker-dry-run-r2-review`
- Diff: `git diff --check cf6cda1..58d8a6e` and aggregate `git diff --check 1d757905..58d8a6e`

## Output

Write full report to `projects/prospereum/reviews/2026-11-12-prospereum-website-pr-1-round2-independent.md` and bounded logs to the matching `-tests.log`. Return verdict, severity counts, exact SHAs, coverage count, command exit codes, artifact paths, and completeness.
