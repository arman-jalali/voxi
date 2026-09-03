# How to Contribute

We'd love to accept your patches and contributions to this project.

External contributions are welcome: bug reports, fixes, and features are all accepted through GitHub pull requests.

There are just a few small guidelines you need to follow.

## Licensing of contributions

By opening a pull request you agree that your contribution is licensed under
the project's [Apache License 2.0](LICENSE). No CLA is required.

## Code Reviews

All submissions, including submissions by project members, require review. We use
GitHub pull requests for this purpose. Consult
[GitHub Help](https://help.github.com/articles/about-pull-requests/) for more
information on using pull requests.

## Community Guidelines

Be kind, be constructive, assume good faith. Harassment of any kind is not
tolerated; maintainers may remove comments or contributors that break this.

## Ground rules

1. **Cleanroom policy.** GPL-licensed projects in this space may be *studied for
   behavior* — never copied. Do not port, translate, or paraphrase their code into
   this repository. You must have the right to contribute the code you submit;
   this rule is the stricter provenance bar that goes with it.
2. **No secrets, ever.** No API keys, tokens, or signing material in code, fixtures,
   tests, or CI files. Voxi has no cloud credentials at all — a change that adds
   one needs a very good reason and will be discussed first.
3. **Design tokens only.** UI changes must use `DesignTokens.swift` /
   `MotionTokens.swift`. If a value isn't in the tokens file, add it there first —
   no magic numbers in views. The full design contract is `docs/design/experience.md`.
4. **Prompt changes need evidence in the PR.** `PromptV1.swift` steers the
   optional flash-lite cleanup pass (Settings › Dictation → Tone). There is no
   automated eval set yet, so verification is by hand and the results belong in
   the PR description: dictate a self-correction, question-shaped speech ("what
   if we shipped it on Friday"), spoken punctuation, and an all-filler take —
   then confirm the ValidationGate did not trip on any of them. Building a real
   eval set is open work and a good first contribution.
5. **Never-lose-words is an invariant, not a feature.** Any change touching audio,
   networking, or insertion must keep these true: audio is on disk before network I/O
   begins; every failure writes a terminal status; errors are never modal; nothing is
   silently discarded.
6. **No telemetry.** PRs adding analytics, tracking, or phone-home behavior of any
   kind will be declined.

## Getting started

```bash
./scripts/install-server.sh          # local Voxtral server (venv + model)
./scripts/build-app.sh               # SwiftPM build → /Applications/Voxi.app
swift test --package-path JotCore    # fast, headless
```

No Xcode required — Command Line Tools are enough.

The failure-mode matrix (`docs/design/product-reliability.md`) and the architecture
contract (`docs/design/architecture.md`) are the best places to understand how the
pieces fit.
