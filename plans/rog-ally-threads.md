# ROG Ally feature work threads

Started 11 November 2026. Scope and sourced comparison: [feature inventory](rog-ally-parity.md). All nine source feature threads were launched and read back as running, each in its own prepared worktree based on `f7194066d`. This is launch status, not a claim that features are implemented or hardware verified.

| Scope | Thread | Branch |
| --- | --- | --- |
| input | [Ally Controller routing, joystick desktop cursor and hardware buttons](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:611a6a8c9217beac148753883d9281cd0bb75d09cd9f14863b5cd2e3bd659c35) | `feat/ally-input-20261111` |
| power | [Ally TDP, battery, cooling and performance controls](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:99446c7af6f88db2094958fe9adb3490ff7bf31e49e1c44aabd77581f7e686a9) | `feat/ally-power-20261111` |
| session | [Ally Proper Gamescope gaming session and desktop switching](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:94616ebbf1194de1dc1778ae977a450ab56d990e63f3ba7f7c3cfdb11b4839ba) | `feat/ally-session-20261111` |
| auth | [Ally Touch keyboard for sign-in, secure unlock and session choice](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:a2e4091cec253abfc7720fdcb20ac6f14cd4c1ea20c78f3841f91de43fdfdcc2) | `feat/ally-auth-20261111` |
| touch | [Ally Desktop floating keyboard and touch ergonomics](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:49e2cad43ef023e2a66dd4374d52f2d72d133a0a2b4c551c02844ab681d0e768) | `feat/ally-touch-20261111` |
| display | [Ally Display, scaling, VRR, docking and capture](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:1474b2beb0859d339d07586295ac69be8a0f06ac657ae6c7abda1cc8019c919d) | `feat/ally-display-20261111` |
| reliability | [Ally Power button, suspend, resume, audio and connectivity](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:48f570197ef90fcf6213a109af8e6c337aa91ba219fb4f18fde35242b2da4636) | `feat/ally-reliability-20261111` |
| games-performance | [Ally Game launchers, compatibility tools and measured performance](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:5707d7c7eb087ee47195571a695be94c2c6f7b597ecb56809b9fe3d87444fedc) | `feat/ally-games-performance-20261111` |
| recovery | [Ally Handheld onboarding, updates, recovery and feature status](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:9a4bd1574cee0b4beef2f40501562ea28787229337800bb145434b0502d9ca7f) | `feat/ally-recovery-20261111` |
| Source integration | [Ally Integrate handheld features and release tested increments](t3-thread://v2/0a3d554a-c5bf-4ee6-94f2-77d755abadaa/mcp:launch:d2eebbb08a9b7c9edc2134e3bebc9b454c70c1f298f9c6254ac91ce359427880) | `feat/ally-parity-release-20261111` |
| Live Ally rollout | [Ally Live rollout and hardware verification](t3-thread://v2/4811d0c9-4fb1-4e7d-ba01-444143bd8f31/mcp:launch:5fe10b7555dcbbfbb26741d26624da5cee482129e846d7aa7a1469a2df071433) | `feat/ally-handheld-rollout-20261111` in the Ally Fleet project |

The source integration thread owns merges and tested release increments. The rollout thread is the sole writer to the live device and owns package installation, configuration backups, UI evidence and rollback. Feature workers send commits and checks to the integrator; they do not independently install or restart services on the Ally.

The common baseline preserves the existing gaming setup, optional wvkbd desktop keyboard and RC71L hardware guards. Eight focused test files passed before launch, with complete logs at `/tmp/ally-baseline-*.log` on the coordinator host. No physical touch/controller acceptance was inferred from these tests.

An additional predicate correction, `28a5d89fc2ecb376cea9f06e66caa69530a5883d`, was reported by source integration after launch. Feature owners must preserve its use of `omarchy-hw-rog-ally` rather than reintroducing product-only checks.

Read the integration and rollout threads for current source and installed results. Initial implementation is in progress; optional, unsupported, pending physical checks and completed features remain distinct.

