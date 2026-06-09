# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- add compact status spinners ([12897cc](https://github.com/satyaborg/devloop/commit/12897ccfc25cc7d11f4778160b718df3673c8ac9))
- pr-review-iterations ([d3bf74a](https://github.com/satyaborg/devloop/commit/d3bf74a89eeeba49feff01c5753ed68ee507cf49))
- launch spec agents interactively ([f2bc531](https://github.com/satyaborg/devloop/commit/f2bc53123a16e65989bd665a8cbf3d172d06f0d0))
- remote-installer ([06a0d77](https://github.com/satyaborg/devloop/commit/06a0d77a11a62d31587df38d3633e4921ec4fa4a))
- add static marketing site ([2f29ceb](https://github.com/satyaborg/devloop/commit/2f29ceba72c1c60a0c1736d26a68a3dc7f4f2d37))
- add why section and tighten install copy ([1ac6d9b](https://github.com/satyaborg/devloop/commit/1ac6d9be6b7f023631e97b8e80df9605de130e8c))
- redesign marketing page to single-column layout ([b18f22d](https://github.com/satyaborg/devloop/commit/b18f22d83d1ed9a671b5ac67b163197210d00661))
- add blog link, pointer cursor on links, drop FAQ dividers ([00ab55b](https://github.com/satyaborg/devloop/commit/00ab55b081cb7f99c2c578fc096b4db33fdf7568))
- add when-(not)-to-use section and author attribution ([2aa69a2](https://github.com/satyaborg/devloop/commit/2aa69a2a9033a9616edaf131c8f8c7b21184734d))
- sharpen FAQ copy and surface the verify hook ([b2e52ae](https://github.com/satyaborg/devloop/commit/b2e52ae3efb13eeff99a46b93303721598556b46))
- switch marketing site font to JetBrains Mono ([3fb7e0a](https://github.com/satyaborg/devloop/commit/3fb7e0a9b1d90291fc58b9bf32ee6a3bc6585677))
- use devloop artifacts in menu flow ([ecd2923](https://github.com/satyaborg/devloop/commit/ecd292388e6e129afe21f2f288c926159de741f3))


### Breaking changes

- add global devloop config defaults ([fe8cd53](https://github.com/satyaborg/devloop/commit/fe8cd53631f966110f388b2a013f25699f80e71b))
- require devloop dependencies ([45ff96c](https://github.com/satyaborg/devloop/commit/45ff96c9a885b3ace7fefb860a6d05319c13d142))


### Fixed

- improve tui back navigation ([73b40a7](https://github.com/satyaborg/devloop/commit/73b40a7665b6da06b49d13c1e071d2adce3b52f7))
- clarify pr mode docs ([cda2477](https://github.com/satyaborg/devloop/commit/cda2477d38e0a4886c300d56a4f2c24b6629fd6e))
- remove dead spec generation path ([46fa3bc](https://github.com/satyaborg/devloop/commit/46fa3bc0bc4d8a24f208c20fffd89cabad06b055))
- remote-installer ([71a3a16](https://github.com/satyaborg/devloop/commit/71a3a164b426249849dfe7b3ff459cacd54cc493))
- populate-draft-pr-body ([6195115](https://github.com/satyaborg/devloop/commit/61951157980550584d14cbb558ed218664b6ff3a))
- de-localize public PR surfaces ([5bb0986](https://github.com/satyaborg/devloop/commit/5bb09867cf896b2614520edfdceb14fcb3cdc162))
- correct grammar and tighten marketing copy ([9b64fcc](https://github.com/satyaborg/devloop/commit/9b64fccfa4b14d1e1289c423c7ee974aeaf87a22))
- render when-section markers as inline SVG and hide decorative markers from screen readers ([0caed06](https://github.com/satyaborg/devloop/commit/0caed06d9a8b408614ac60304cff1e6fdb97f944))

## [0.2.0](https://github.com/satyaborg/devloop/releases/tag/v0.2.0) - 2026-05-30

### Added

- initial implementation ([96901ee](https://github.com/satyaborg/devloop/commit/96901ee67cbe8e01e4fe25cea9807d100dc94f59))
- reuse agent sessions in devloop ([6cf72c5](https://github.com/satyaborg/devloop/commit/6cf72c59df7acf8ae95e66e882e7e05898365abd))
- port devloop to bun opentui ([38cf9bd](https://github.com/satyaborg/devloop/commit/38cf9bde799ec7e8c5b47b261e0ff986a14dd67f))
- show default cli welcome ([4e55181](https://github.com/satyaborg/devloop/commit/4e551816a2446ac041100b22c988eaa0e3e5a398))
- run devloop in isolated worktrees ([17b7fd5](https://github.com/satyaborg/devloop/commit/17b7fd5ac76ee90feb601efd11ac4b902bd73c99))
- derive semantic work names ([0bb4bf0](https://github.com/satyaborg/devloop/commit/0bb4bf0411c854f872038c0ca22826582dd65b40))
- show tui step progress ([fcfe52a](https://github.com/satyaborg/devloop/commit/fcfe52af09db5c6b6d3dbecb3e170a9849a860ac))
- bundle spec generation skill ([a4ae43d](https://github.com/satyaborg/devloop/commit/a4ae43d45cb9e8e3cbfb01ebde03e94bf67fd3a2))
- configure coder and reviewer agents ([f00c2ae](https://github.com/satyaborg/devloop/commit/f00c2aee76b55f15a98c806e20a527c0062420f5))
- require evidence-rich review matrices ([1f31f70](https://github.com/satyaborg/devloop/commit/1f31f7077da79fcca2ec1219252c3d0e7ce37373))
- automate pass commits and prs ([4c222a7](https://github.com/satyaborg/devloop/commit/4c222a72eaa73535777ed0dfbe789902f704589b))
- npm-release-readiness ([057aef0](https://github.com/satyaborg/devloop/commit/057aef0fc8e715952c394af4be8ba3fc6ba59b1d))
- force maximum agent effort ([51af634](https://github.com/satyaborg/devloop/commit/51af634d573774b6a88d722927f3460c4081d854))
- add bash devloop runtime ([f6611e0](https://github.com/satyaborg/devloop/commit/f6611e00c480058014b73708ab7bfdae6eefc5cc))
- add adversarial review gates ([5143efd](https://github.com/satyaborg/devloop/commit/5143efd46713e0b95b6e550d9e702fb2a814fba5))
- overhaul interactive cli ui ([3d0f033](https://github.com/satyaborg/devloop/commit/3d0f0332592b1a68a4e3606249ca82013b7ba506))
- configure spec directories ([c8a7cbd](https://github.com/satyaborg/devloop/commit/c8a7cbdc1ee272f8baae9e146a180d271d55de94))
- add scoped devloop config ([00868e6](https://github.com/satyaborg/devloop/commit/00868e6532e87e1663340c187bee34872a2db38e))
- simplify spec path settings ([1e1213c](https://github.com/satyaborg/devloop/commit/1e1213cafabe8f984e45ee8212e3585bd768d15f))
- polish interactive tui ([a4485ae](https://github.com/satyaborg/devloop/commit/a4485ae3022a827275bed4870128a6ebeda2ff2c))
- add release versioning ([30c7297](https://github.com/satyaborg/devloop/commit/30c72976c1ac89e09788e799dac3aa4571871203))
- harden devloop validation loop ([56bd2d5](https://github.com/satyaborg/devloop/commit/56bd2d56026ec94c179cde22fe6f0debeae307b7))


### Breaking changes

- install skills for codex and claude ([eb2cb6d](https://github.com/satyaborg/devloop/commit/eb2cb6de9f988ea2acac988f7f1fb782a25a39ba))


### Documentation

- add repository guidelines ([447dd0c](https://github.com/satyaborg/devloop/commit/447dd0ce63264b1fc9cc124eaa975fa179ee3e76))
- link claude guide to agents ([70be06e](https://github.com/satyaborg/devloop/commit/70be06eebb326baaa54ff5eb4d8c6199f074d029))
- clarify worktree cleanup ([3dc7b1b](https://github.com/satyaborg/devloop/commit/3dc7b1b239684e17683c04f8e0f3ba15c2d16b0e))
- add license section ([ac82872](https://github.com/satyaborg/devloop/commit/ac8287290a2f7dae956248fc46411e9ac9cacf8b))


### Fixed

- surface devloop commit failures ([493031a](https://github.com/satyaborg/devloop/commit/493031ab90ba593ad2bc904ec3d8c0ba1fd92b96))
- clarify worktree outputs ([6e1067a](https://github.com/satyaborg/devloop/commit/6e1067acf5cf0298a3e3c825176f190cbb346bbb))
- clean up naming temp logs ([424a502](https://github.com/satyaborg/devloop/commit/424a502fe78441e6b9e9877f719bc876acbd2210))
- align tui navigation labels ([3f74b90](https://github.com/satyaborg/devloop/commit/3f74b90b0d87294c5224f33888f6c05346ba1397))
- derive report subtitles from specs ([1984ca6](https://github.com/satyaborg/devloop/commit/1984ca6b8e82dfdd3689df864fc1108d38ec2517))
- add topical report haiku ([2cd843d](https://github.com/satyaborg/devloop/commit/2cd843df292217f676e59b3631d7f6d922d3a1db))
- key sessions by configured agent ([16ef419](https://github.com/satyaborg/devloop/commit/16ef419de2429bc4569fc7789fb4fb1998aefc0f))
- align release readiness tests ([8d9f0bf](https://github.com/satyaborg/devloop/commit/8d9f0bf14d5ca4be0096e01cca8ca19d140f270b))
- harden bash runtime helpers ([7fb28cc](https://github.com/satyaborg/devloop/commit/7fb28cc7f7da3788d7ef3a233242465ad4a8e2c9))
- preserve interactive run status ([48cadbb](https://github.com/satyaborg/devloop/commit/48cadbb140662919f6ae8ce6597274cf755d13a1))
- compute release bumps ([167b903](https://github.com/satyaborg/devloop/commit/167b903c58b5fbbc2658136e13eb42214cab54f2))
- classify clean devloop worktrees ([546a59b](https://github.com/satyaborg/devloop/commit/546a59bac144e061a61d671770c7209a6dd4a76c))

