# Contributing

When contributing to this repository, please first discuss the change you wish to
make via issue, email, or any other method with the owners of this repository
before making a change.

Please note we have a code of conduct; please follow it in all your interactions
with the project.

## Development

This repository ships devcontainer Features — shell scripts and container metadata, no
application code. Read [CLAUDE.md](CLAUDE.md) before changing anything under
`features/`; the build-time versus create-time split and the option-recording mechanism
are the two things that catch people out.

Open the repository in its devcontainer. It consumes the `devbase` Feature **from the
working tree**, so your environment is built from the code you are editing — a change
that breaks the Feature breaks your own shell on the next rebuild. That is deliberate.

Before opening a pull request:

```sh
pnpm lint            # prettier + shellcheck + feature metadata + actionlint
pnpm features:test   # real container builds: default options + every scenario
```

`pnpm features:test` needs a Docker daemon; the devcontainer includes docker-in-docker
for that. While iterating, `pnpm features:test -- --filter <scenario>` runs one scenario
instead of the suite.

### Changing a Feature

**Do not edit `version` in `devcontainer-feature.json` by hand.** semantic-release owns
it: the release workflow derives the next version from your commit types and writes it
into that file, then publishes it in the same run. A hand-edited version either gets
overwritten or collides with the next release.

What that means is that **your commit type decides what consumers get**, so pick it
deliberately:

| Commit                                  | Result for a consumer pinned to `:1`                  |
| --------------------------------------- | ----------------------------------------------------- |
| `fix(devbase): …`                       | patch — picked up on their next rebuild               |
| `feat(devbase): …`                      | minor — picked up on their next rebuild               |
| `feat(devbase): …` + `BREAKING CHANGE:` | major — **not** picked up until they change their pin |
| `ci` / `docs` / `chore` / `test` / …    | nothing published                                     |

A removed or renamed option, or a changed default that alters what an existing consumer
already gets, is a `BREAKING CHANGE:` and needs a migration note in the README. Anything
inside `1.x` reaches every repository automatically, so the major is a real contract.

And one rule that is yours, not the tooling's:

- **A new option needs a test scenario.** Otherwise nothing proves the opt-out actually
  opts out, and an option that silently does nothing is worse than no option.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) with a **mandatory
scope**:

```text
<type>(<scope>): <summary>
```

Scope is normally the Feature id — `fix(devbase): …`, `feat(devbase): …`. Everything else takes a non-releasing type:

| Type       | Use for                                         |
| ---------- | ----------------------------------------------- |
| `fix`      | a bug fix in the source — **releases a patch**  |
| `feat`     | a feature in the source — **releases a minor**  |
| `ci`       | workflows, devcontainer                         |
| `build`    | build tooling and scripts                       |
| `docs`     | documentation only                              |
| `test`     | tests only                                      |
| `refactor` | internal restructuring with no behaviour change |
| `chore`    | anything else                                   |

`cz` (commitizen) is installed in the devcontainer and will prompt for the parts.

**Breaking changes** add a `BREAKING CHANGE: <summary>` line to the commit body,
after a blank line. That triggers a major bump, so it also needs a migration note
for consumers in the same change.

Do **not** add `Co-Authored-By:` trailers.

## Branches and pull requests

- Branch from an up-to-date default branch: `git checkout main && git pull --ff-only`
  before `git checkout -b`. Never branch from a stale local default branch or from
  another feature branch.
- Name branches after the Jira issue: `RSRMID-1234/short-description`.
- Include the Jira issue link in the PR description, and add the PR URL as a comment
  on the Jira issue after opening it.
- **Rebase-merge** (`gh pr merge --rebase`). Squash merges are disabled at the
  repository level, because the release tooling reads the individual commits.

## Formatting

Prettier owns everything it understands (Markdown, JSON, YAML) and runs in CI, not
just as a local nag — unformatted Markdown is a red build. The pre-commit hook runs
`lint-staged` over what you staged, so in practice it is fixed before it reaches CI.

## Code of Conduct

### Our Pledge

In the interest of fostering an open and welcoming environment, we as contributors
and maintainers pledge to making participation in our project and our community a
harassment-free experience for everyone, regardless of age, body size, disability,
ethnicity, gender identity and expression, level of experience, nationality,
personal appearance, race, religion, or sexual identity and orientation.

### Our Standards

Examples of behavior that contributes to creating a positive environment include:

- Using welcoming and inclusive language
- Being respectful of differing viewpoints and experiences
- Gracefully accepting constructive criticism
- Focusing on what is best for the community
- Showing empathy towards other community members

Examples of unacceptable behavior by participants include:

- The use of sexualized language or imagery and unwelcome sexual attention or
  advances
- Trolling, insulting/derogatory comments, and personal or political attacks
- Public or private harassment
- Publishing others' private information, such as a physical or electronic address,
  without explicit permission
- Other conduct which could reasonably be considered inappropriate in a professional
  setting

### Our Responsibilities

Project maintainers are responsible for clarifying the standards of acceptable
behavior and are expected to take appropriate and fair corrective action in response
to any instances of unacceptable behavior.

Project maintainers have the right and responsibility to remove, edit, or reject
comments, commits, code, wiki edits, issues, and other contributions that are not
aligned to this Code of Conduct, or to ban temporarily or permanently any
contributor for other behaviors that they deem inappropriate, threatening,
offensive, or harmful.

### Scope

This Code of Conduct applies both within project spaces and in public spaces when an
individual is representing the project or its community. Examples of representing a
project or community include using an official project e-mail address, posting via
an official social media account, or acting as an appointed representative at an
online or offline event. Representation of a project may be further defined and
clarified by project maintainers.

### Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported
by contacting the project team. All complaints will be reviewed and investigated and
will result in a response that is deemed necessary and appropriate to the
circumstances. The project team is obligated to maintain confidentiality with regard
to the reporter of an incident. Further details of specific enforcement policies may
be posted separately.

Project maintainers who do not follow or enforce the Code of Conduct in good faith
may face temporary or permanent repercussions as determined by other members of the
project's leadership.

### Attribution

This Code of Conduct is adapted from the [Contributor Covenant][homepage], version
1.4, available at [http://contributor-covenant.org/version/1/4][version]

[homepage]: http://contributor-covenant.org
[version]: http://contributor-covenant.org/version/1/4/
