# Sync agent rules and skills across machines

One repo holds your agent rules and skills. Ansible copies them to every machine over SSH. Each coding agent finds them in the folder it already reads. Nothing is overwritten if someone edited it by hand on the machine.

Works with Codex, Claude Code, OpenCode, Grok and Muse Code, on any number of machines and any number of accounts per provider.

> **Em português:** este repo descreve um método para manter regras e skills de agentes iguais em várias máquinas e várias contas. As regras saem de uma base comum mais o papel da máquina. As skills saem de um snapshot revisado, com checksums. O Ansible distribui tudo por SSH e cada agente encontra os arquivos na pasta que já lê. Se alguém mudou um arquivo gerenciado direto na máquina, o deploy para em vez de sobrescrever. Para usar: aponte seu agente para este README e peça para ele seguir a seção **Instructions for agents**.

- [How it works](#how-it-works)
- [Where each agent looks](#where-each-agent-looks)
- [Multiple accounts per provider](#multiple-accounts-per-provider)
- [Safety](#safety)
- [Example layout](#example-layout)
- [Instructions for agents](#instructions-for-agents)
- [Verification checklist](#verification-checklist)
- [Limits](#limits)
- [References](#references)

## How it works

Rules and skills are different things, so they take different paths.

**Rules** are always-on instructions, the content of `AGENTS.md` and `CLAUDE.md`.

1. Write one common base (`rules/base.md`).
2. Add one short file per machine role (`rules/roles/workstation.md`, `rules/roles/server.md`, …).
3. On deploy, base + role are rendered into one file and written where each agent reads its global rules: `AGENTS.md` for Codex and OpenCode, `CLAUDE.md` for Claude Code.

**Skills** are folders with a `SKILL.md` that agents load on demand.

1. Keep every skill in one source folder (`skills/<name>/SKILL.md`).
2. After reviewing changes, record a snapshot: one sha256 per skill folder, saved in `skills.lock`. Deploys use only what the snapshot approved.
3. On deploy, each skill is copied to a local folder on the machine (for example `~/.local/share/agent-sync/skills/<name>`).
4. Symlinks expose that local copy in each agent's skills folder. A local copy instead of a link to a network path means skills still work when the controller is offline.

**Distribution** is plain Ansible over SSH. The controller is any machine with the repo checked out and SSH access to the others. Machines need only SSH and a POSIX shell. They don't need Ansible installed.

```
            repo (source of truth)
   rules: base + role      skills + skills.lock
                   │
             Ansible over SSH
                   │
   ┌───────────────┼───────────────┐
machine A      machine B       machine C
   │
   ├─ ~/.codex/AGENTS.md, ~/.config/opencode/AGENTS.md, ~/.claude/CLAUDE.md   (rules)
   ├─ ~/.local/share/agent-sync/skills/<name>                                 (local copy)
   ├─ ~/.agents/skills/<name>  → local copy    Codex, OpenCode, Grok, Muse Code
   └─ ~/.claude/skills/<name>  → local copy    Claude Code (+ one per profile)
```

## Where each agent looks

User-level (all projects) locations, checked against each tool's docs on 2026-11-08. Docs change, so re-check the [References](#references) before relying on a path.

| Agent | Skills folder this setup uses | Other user-level skills folders | Global rules file | Symlinked skill folders |
| --- | --- | --- | --- | --- |
| Codex | `~/.agents/skills` | `/etc/codex/skills` (admin) | `$CODEX_HOME/AGENTS.md` (default `~/.codex/AGENTS.md`) | Documented as supported |
| Claude Code | `~/.claude/skills` | — | `~/.claude/CLAUDE.md` | Documented as supported |
| OpenCode | `~/.agents/skills` | `~/.config/opencode/skills`, `~/.claude/skills` | `~/.config/opencode/AGENTS.md` (falls back to `~/.claude/CLAUDE.md` when missing) | Not stated in docs. Test it |
| Grok | `~/.agents/skills` | `~/.grok/skills`, and Claude Code's skills | User-level path not stated on the skills page. Grok reads `AGENTS.md` and `CLAUDE.md` in projects | Not stated in docs. Test it |
| Muse Code | `~/.agents/skills` | `$XDG_CONFIG_HOME/muse/skills`; also `~/.claude/skills` and `$CODEX_HOME/skills` unless turned off | User-level path not stated in the docs. Project rules use `AGENTS.md` / `CLAUDE.md` | Not stated in docs. Test it |

Notes:

- `~/.agents/skills` is the one folder four of the five agents read, so it is the main target. Claude Code needs `~/.claude/skills`.
- OpenCode, Grok and Muse Code also read Claude's folders. They may list a skill twice when it is linked in both places. Both links point at the same copy, so the content is identical. Claude Code documents that it loads a skill once even when several locations point at the same target. The other tools don't document this.
- Claude Code reserves the folder name `synced` inside `~/.claude/skills`. Don't name a skill `synced`.
- Claude Code cloud and Cowork sessions don't read `~/.claude/skills` on your machine. This setup covers local sessions only.

## Multiple accounts per provider

Use one profile directory per account. Every profile gets the **same rules and skills**, and its **own sign-in**.

- **Codex:** set `CODEX_HOME` per account, for example `CODEX_HOME=~/.codex-work codex`. Each home gets its own `AGENTS.md` from the deploy. Skills come from `~/.agents/skills`, which sits outside every Codex home, so all accounts share them automatically.
- **Claude Code:** set `CLAUDE_CONFIG_DIR` per account, for example `alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'`. Claude's docs show exactly this for running accounts side by side. The deploy writes `CLAUDE.md` and links `skills/<name>` into every config dir you list. The docs say settings, history and plugins live under that dir. They don't spell out skills and `CLAUDE.md`, so run `/skills` in each profile once to confirm.
- **OpenCode, Grok, Muse Code:** this guide doesn't cover multi-account setups for them. They read `~/.agents/skills`, so every account on the machine sees the same skills.

**Shared config is not shared login.** The repo carries rules, skills and non-secret config only. Sign in to every account on every machine with that tool's own login flow. Never copy sign-in files, tokens or API keys into the repo or between machines with this tool. Inside a profile directory, the deploy touches only the files it manages (`AGENTS.md`/`CLAUDE.md` and `skills/<name>` links). It leaves everything else alone.

## Safety

The deploy has two jobs besides copying: **refuse** and **verify**.

**Refuse to overwrite unreviewed local changes.**

- After every successful deploy, each machine stores a manifest (`manifest.json`) with the sha256 of every file and skill folder it wrote.
- Before the next deploy, the machine re-hashes those files. If one no longer matches the manifest, someone changed it by hand. The deploy stops and lists the files. Nothing gets written.
- On a machine's first deploy there is no manifest. Any existing file that differs from the new content also stops the deploy. To take those files over, back them up and run once with `agent_sync_adopt_existing=true`.
- The deploy won't replace a real folder with a symlink. If `~/.agents/skills/<name>` is already a folder someone made by hand, the run fails instead of deleting it.
- The controller checks that `skills/` still matches `skills.lock`, so an edit nobody reviewed can't ship.
- Rendered rules start with a "managed file, edit the repo" comment so a person who opens the file knows where to change it.

**Verify after apply.**

- Re-hash every rules file and compare it to the rendered content.
- Re-hash every local skill copy and compare it to `skills.lock`.
- Check every link is a symlink that points at the expected local copy and that `SKILL.md` is readable through it.

## Example layout

A complete, minimal example lives in [`skills-sync/example/`](skills-sync/example/). It uses only `ansible-core` builtin modules. It was tested with `ansible-core` 2.22 against a scratch home directory on Linux. The tests covered a first deploy, a second run with no changes, check mode, and the four failure cases: local edits, unreviewed skill changes, hand-written files and same-name folders. It was not tested on macOS or over real SSH.

```
skills-sync/example/
├── ansible.cfg
├── inventory.example.ini        # copy to inventory.ini (git-ignored)
├── site.yml
├── rules/
│   ├── base.md
│   └── roles/{workstation,server}.md
├── skills/<name>/SKILL.md
├── skills.lock                  # written by scripts/snapshot.sh
├── scripts/
│   ├── tree-hash.sh             # one sha256 per folder, same on Linux and macOS
│   └── snapshot.sh
└── roles/agent_sync/
    ├── defaults/main.yml        # paths, profiles, role
    ├── templates/rules.md.j2    # base + role
    └── tasks/{main,guard,verify}.yml
```

The important variables (`roles/agent_sync/defaults/main.yml`):

```yaml
agent_sync_role: workstation                 # picks rules/roles/<role>.md
agent_sync_codex_homes: ["~/.codex"]         # add one per extra Codex account
agent_sync_claude_dirs: ["~/.claude"]        # add one per extra Claude account
agent_sync_agents_skills_dir: "~/.agents/skills"
agent_sync_opencode_rules: "~/.config/opencode/AGENTS.md"
agent_sync_state_dir: "~/.local/share/agent-sync"
agent_sync_adopt_existing: false
```

(The real defaults use `{{ ansible_facts.env.HOME }}` instead of `~`.)

The task order in `tasks/main.yml`:

1. Load `skills.lock` and render the rules (base + role).
2. On the controller, check that `skills/` still matches `skills.lock`.
3. Install the hash helper on the machine.
4. Guard: compare the managed files with the last manifest and stop on any difference.
5. Write the rules files. Replace any skill copy whose hash differs from the lock.
6. Create the skills folders and link each skill into each one (`force` off).
7. Write the new manifest.
8. Verify the contents and links.

## Instructions for agents

You are setting this up for a user. Follow these steps in order. Stop and ask the user wherever a step says **ask**.

**Ground rules**

- Never read, print, copy or commit credentials, tokens, API keys, SSH private keys or agent sign-in files.
- Never put real hostnames, IPs, usernames or account names in a file that may become public. Keep them in `inventory.ini`, which stays git-ignored.
- Never delete or overwrite an existing rules file or skill folder without a backup and the user's OK.
- Before linking or editing anything, re-check the agent paths against the [References](#references). If a doc disagrees with this README, the doc wins.

**Steps**

1. **Ask** the user:
   - Which machines (and their SSH aliases) should be included?
   - What role does each machine have? Workstation and server are the usual ones.
   - Which agents does each machine run?
   - How many accounts per provider are there, and which profile directories do they use (`CODEX_HOME`, `CLAUDE_CONFIG_DIR`)?
2. On the controller, make sure `ansible-core` is installed, then check every machine answers over SSH: `ansible all -m ansible.builtin.ping`. Fix SSH first if any fails. This setup does not create SSH access or keys.
3. Create the user's own **private** repo from `skills-sync/example/`. Copy `inventory.example.ini` to `inventory.ini` and fill in the machines. Put the role and profile lists in `group_vars/` or `host_vars/`.
4. **Inventory before changing anything.** On each machine, list what already exists in `~/.agents/skills`, `~/.claude/skills`, each Claude config dir's `skills/`, `~/.codex/AGENTS.md` (and each extra `CODEX_HOME`), `~/.config/opencode/AGENTS.md`, and `~/.claude/CLAUDE.md`. Show the list to the user.
5. Move what the user wants to keep into the repo:
   - Rules shared by every machine go in `rules/base.md`.
   - Rules for one kind of machine go in `rules/roles/<role>.md`.
   - Each skill becomes a folder in `skills/<name>/` with a `SKILL.md` that has `name` and `description` in its frontmatter.
   - Copy only text the user wrote. Skip secrets and anything machine-specific.
6. Run `scripts/snapshot.sh`. Show the user the diff of `skills/` and `skills.lock` and **ask** them to review it. Then commit.
7. Dry run first: `ansible-playbook site.yml --check --diff --limit <one-machine>`. Look for unexpected targets. On a machine that was never deployed, check mode stops at the link step because the local copies don't exist yet, which is expected.
8. Deploy to one machine: `ansible-playbook site.yml --limit <one-machine>`.
   - If the guard stops the run, show the user the listed files.
   - Either move those changes into the repo, or back the files up and re-run with `-e agent_sync_adopt_existing=true`. **Ask** before using adopt.
9. Run the [verification checklist](#verification-checklist) on that machine.
10. Deploy to the rest: `ansible-playbook site.yml`. Run it a second time and confirm it reports `changed=0`.
11. To change a skill or rule later: edit the repo, run `scripts/snapshot.sh` if skills changed, review, commit, deploy. Never edit the deployed copies.

## Verification checklist

Per machine:

- [ ] The playbook finished with `failed=0`, and a second run reported `changed=0`.
- [ ] `~/.local/share/agent-sync/manifest.json` exists and lists every rules file and skill.
- [ ] `ls -l ~/.agents/skills ~/.claude/skills` shows every skill as a link into `~/.local/share/agent-sync/skills/`. Repeat for each extra Claude config dir.
- [ ] Each rules file starts with the "Managed by agent-sync" line and contains base + the right role.
- [ ] Each agent lists the skills in a **new** session (old sessions may not reload):
  - Codex: `/skills` (repeat with each `CODEX_HOME`).
  - Claude Code: `/skills` (repeat with each `CLAUDE_CONFIG_DIR`).
  - OpenCode: mention a skill as `@<skill-id>` and confirm it loads.
  - Grok: open `/skills`.
  - Muse Code: `muse skills list`.
- [ ] Each agent quotes the global rules when asked "Summarize your current instructions."
- [ ] Guard test: append a line to one deployed rules file, run the playbook, and confirm it stops and names that file. Then undo the edit.
- [ ] `git status` in the repo shows no inventory with real hosts, and `git grep -iE "token|secret|password|api[_-]?key"` finds nothing sensitive.

## Limits

- Removing a skill from the repo doesn't remove its links or local copy. Delete them by hand, or add a cleanup task that removes only names recorded in the old manifest.
- A file on disk doesn't mean a running session loaded it. Start a new session after a deploy.
- Machines that are offline are simply skipped. Run the playbook again when they are back.
- MCP servers and plugins are out of scope. Their config can be shared the same way, but their sign-ins and OS permissions stay per machine.
- Windows is untested. The example assumes macOS or Linux machines with a POSIX shell.

## References

- Codex skills: <https://developers.openai.com/codex/skills/>
- Codex `AGENTS.md` and `CODEX_HOME`: <https://developers.openai.com/codex/guides/agents-md>
- Claude Code skills: <https://code.claude.com/docs/en/skills>
- Claude Code memory (`~/.claude/CLAUDE.md`): <https://code.claude.com/docs/en/memory>
- Claude Code environment variables (`CLAUDE_CONFIG_DIR`): <https://code.claude.com/docs/en/env-vars>
- OpenCode skills: <https://opencode.ai/docs/skills/>
- OpenCode rules: <https://opencode.ai/docs/rules/>
- Grok skills, plugins and marketplaces: <https://docs.x.ai/build/features/skills-plugins-marketplaces>
- Muse Code extending (skills): <https://dev.meta.ai/docs/muse-code/extending>
- Muse Code configuration (instruction files): <https://dev.meta.ai/docs/muse-code/configuration>
- Ansible builtin modules: <https://docs.ansible.com/ansible/latest/collections/ansible/builtin/>
