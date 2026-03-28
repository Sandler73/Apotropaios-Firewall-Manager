# Contributor Covenant Code of Conduct

<p align="center">
  <img src="https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa?style=flat-square" alt="Contributor Covenant 2.1">
  <img src="https://img.shields.io/badge/enforcement-4%20levels-informational?style=flat-square" alt="4 Enforcement Levels">
</p>

---

## Table of Contents

- [Our Pledge](#our-pledge)
- [Our Standards](#our-standards)
  - [Positive Behaviors](#positive-behaviors)
  - [Unacceptable Behaviors](#unacceptable-behaviors)
- [Responsible Use Policy](#responsible-use-policy)
- [Scope](#scope)
- [Contributor Rights and Responsibilities](#contributor-rights-and-responsibilities)
- [Intellectual Property and Attribution](#intellectual-property-and-attribution)
- [Enforcement](#enforcement)
  - [Reporting](#reporting)
  - [Confidentiality](#confidentiality)
  - [Enforcement Guidelines](#enforcement-guidelines)
  - [Appeal Process](#appeal-process)
- [Security-Specific Provisions](#security-specific-provisions)
- [Maintainer Responsibilities](#maintainer-responsibilities)
- [Attribution](#attribution)

---

## Our Pledge

We as members, contributors, and maintainers pledge to make participation in the
Apotropaios project and community a harassment-free experience for everyone,
regardless of age, body size, visible or invisible disability, ethnicity, sex
characteristics, gender identity and expression, level of experience, education,
socio-economic status, nationality, personal appearance, race, caste, color,
religion, or sexual identity and orientation.

We pledge to act and interact in ways that contribute to an open, welcoming,
diverse, inclusive, and healthy community focused on building secure, reliable
software that protects the networks and systems of its users.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Our Standards

### Positive Behaviors

Examples of behavior that contributes to a positive environment for our community:

- Demonstrating empathy and kindness toward other people
- Being respectful of differing opinions, viewpoints, and experiences
- Giving and gracefully accepting constructive feedback
- Accepting responsibility and apologizing to those affected by our mistakes,
  and learning from the experience
- Focusing on what is best not just for us as individuals, but for the overall
  community and the security of systems that depend on this software
- Providing clear, detailed bug reports with reproduction steps
- Writing thorough pull request descriptions and responding to review feedback
  constructively
- Helping newcomers understand the project's architecture and security
  requirements
- Acknowledging the contributions of others in commit messages and release notes
- Prioritizing security and correctness over feature velocity
- Proactively documenting the security implications of changes
- Sharing knowledge about firewall management, network security, and
  defense-in-depth principles

### Unacceptable Behaviors

Examples of unacceptable behavior:

- The use of sexualized language or imagery, and sexual attention or advances of
  any kind
- Trolling, insulting or derogatory comments, and personal or political attacks
- Public or private harassment, intimidation, or threats
- Publishing others' private information, such as a physical or email address,
  without their explicit permission (doxxing)
- Deliberately introducing security vulnerabilities, backdoors, or malicious
  code into the project
- Publicly disclosing security vulnerabilities before a fix is available (see
  [SECURITY.md](SECURITY.md) for coordinated disclosure procedures)
- Misrepresenting the security properties of the software or its components
- Submitting contributions that deliberately undermine the security, integrity,
  or reliability of the framework
- Using the project's communication channels for commercial solicitation,
  spam, or off-topic promotion
- Sustained disruption of project discussions or processes
- Advocating for, or encouraging, any of the above behaviors
- Other conduct which could reasonably be considered inappropriate in a
  professional setting

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Responsible Use Policy

Apotropaios is a **defensive security tool** designed for authorized systems
administration, network security management, and firewall configuration. This
project exists to help administrators protect networks and systems.

### Expected Use

Participants in this project are expected to use, promote, and contribute to the
software for:

- Authorized systems administration and network management
- Firewall configuration and security hardening
- Network defense and access control
- Compliance auditing and security verification
- Educational purposes and security research on authorized systems
- Testing in controlled, isolated lab environments

### Prohibited Use

The following uses are prohibited and may result in enforcement action:

- Using the software to disrupt, deny service to, or gain unauthorized access
  to systems or networks you do not own or have explicit authorization to manage
- Providing guidance, instructions, or assistance within project communication
  channels for using the software in unauthorized or illegal activities
- Distributing modified versions of the software that remove security controls,
  introduce backdoors, or enable unauthorized access
- Misrepresenting the tool's capabilities to facilitate harm to others

### No Liability for Misuse

The project maintainers and community are not responsible for any misuse of the
software. Users are solely responsible for ensuring their use complies with all
applicable laws and regulations. See [LICENSE](LICENSE) for full terms.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Scope

This Code of Conduct applies within all project spaces, including:

- The GitHub repository (issues, pull requests, discussions, wiki, code review
  comments)
- Project communication channels (if established: mailing lists, chat rooms,
  forums, Discord/Slack servers)
- Project events (if established: meetups, conferences, presentations,
  workshops)
- Any public space where an individual is representing the project or its
  community
- Private correspondence related to project business or Code of Conduct
  matters

Examples of representing the project include using an official project email
address, posting via an official social media account, acting as an appointed
representative at an online or offline event, or being listed as a project
maintainer or contributor.

This Code of Conduct does not apply to activity outside of project spaces
that has no connection to the project, unless such activity constitutes
harassment of a project member related to their participation in the project.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Contributor Rights and Responsibilities

### Rights

Every contributor has the right to:

- Be treated with respect, dignity, and professionalism
- Have their contributions evaluated on technical merit, not personal
  characteristics
- Receive clear, constructive feedback on their contributions
- Understand why a contribution was accepted, modified, or rejected
- Disagree with technical decisions respectfully and have disagreements
  resolved through transparent discussion
- Be credited for their contributions in accordance with the project's
  attribution practices
- Withdraw from the project at any time without prejudice

### Responsibilities

Every contributor has the responsibility to:

- Follow this Code of Conduct in all project interactions
- Act in good faith when contributing code, documentation, or feedback
- Disclose potential conflicts of interest that may affect their contributions
- Report security vulnerabilities through the coordinated disclosure process
  described in [SECURITY.md](SECURITY.md)
- Not submit contributions they know to be incorrect, insecure, or harmful
- Respect the time and effort of maintainers and other contributors
- Accept that maintainers have final authority on technical decisions for the
  project, even when contributors disagree

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Intellectual Property and Attribution

### Original Work

By submitting contributions to this project, you represent that:

- Your contributions are your original work, or you have the right to submit
  them
- Your contributions do not infringe upon the intellectual property rights of
  any third party
- You have the authority to grant the licenses described in [LICENSE](LICENSE)

### Attribution

- Contributors will be credited through git commit history
- Significant contributions may be acknowledged in release notes and the
  [changelog](docs/changelog.md)
- The project does not guarantee specific forms of credit beyond standard git
  attribution
- Do not add your name to source files — git history serves as the canonical
  attribution record

### License Compliance

All contributions must be compatible with the project's MIT License. If your
contribution includes code derived from other open-source projects, you must:

- Verify license compatibility before submitting
- Clearly identify the source and license of derived code in your pull request
- Include any required attribution notices

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Enforcement

### Reporting

Instances of abusive, harassing, or otherwise unacceptable behavior may be
reported to the project maintainers through the following channels:

- **GitHub Private Reporting**: Use
  [GitHub's private vulnerability reporting](https://github.com/Sandler73/Apotropaios-Firewall-Manager/security/advisories/new)
  for Code of Conduct violations that require confidentiality
- **GitHub Issues**: For non-sensitive Code of Conduct matters, open an issue
  with the "code of conduct" label
- **Email**: Contact the project maintainers directly (addresses available in
  the repository's maintainer list)

All complaints will be reviewed and investigated promptly and fairly.

### Confidentiality

All reports will be treated with confidentiality to the extent possible:

- The identity of the reporter will not be disclosed without their explicit
  consent, except as required by law
- Details of the incident will be shared only with those involved in the
  investigation and enforcement decision
- The accused party will be informed of the specific allegations against them
  and given an opportunity to respond before enforcement action is taken
- Records of Code of Conduct investigations will be retained by maintainers
  for a reasonable period to track patterns of behavior

### Enforcement Guidelines

Maintainers will follow these guidelines in determining the consequences for
any action they deem in violation of this Code of Conduct:

#### 1. Correction

**Community Impact**: Use of inappropriate language or other behavior deemed
unprofessional or unwelcome in the community.

**Consequence**: A private, written warning from maintainers, providing clarity
around the nature of the violation and an explanation of why the behavior was
inappropriate. A public apology may be requested.

#### 2. Warning

**Community Impact**: A violation through a single incident or series of
actions.

**Consequence**: A warning with consequences for continued behavior. No
interaction with the people involved, including unsolicited interaction with
those enforcing the Code of Conduct, for a specified period of time. This
includes avoiding interactions in community spaces as well as external channels
like social media. Violating these terms may lead to a temporary or permanent
ban.

#### 3. Temporary Ban

**Community Impact**: A serious violation of community standards, including
sustained inappropriate behavior.

**Consequence**: A temporary ban from any sort of interaction or public
communication with the community for a specified period of time. No public or
private interaction with the people involved, including unsolicited interaction
with those enforcing the Code of Conduct, is allowed during this period.
Violating these terms may lead to a permanent ban.

#### 4. Permanent Ban

**Community Impact**: Demonstrating a pattern of violation of community
standards, including sustained inappropriate behavior, harassment of an
individual, or aggression toward or disparagement of classes of individuals.
Also applies to the deliberate introduction of malicious code or security
vulnerabilities.

**Consequence**: A permanent ban from any sort of public interaction within
the community. All pending contributions will be rejected. Access to project
repositories and communication channels will be revoked.

### Appeal Process

Contributors who receive enforcement action have the right to appeal:

1. **Timeframe**: Appeals must be submitted within 14 calendar days of the
   enforcement notification
2. **Submission**: Appeals should be sent via the same reporting channel used
   for the original notification, addressed to the project maintainers
3. **Content**: The appeal should include the specific enforcement action being
   appealed, the basis for the appeal (new information, procedural error, or
   disproportionate response), and any supporting evidence
4. **Review**: Appeals will be reviewed by a maintainer not involved in the
   original decision, if one is available. If all maintainers were involved,
   the appeal will be reviewed collectively with the new information considered
5. **Decision**: The appeal decision is final and will be communicated within
   30 calendar days of receipt
6. **Scope**: During the appeal process, the original enforcement action
   remains in effect

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Security-Specific Provisions

Given that Apotropaios is a security tool that manages critical network
infrastructure at the kernel level, the following additional provisions apply:

### 1. Coordinated Disclosure

Participants who discover security vulnerabilities in the Apotropaios framework
must follow the coordinated disclosure process described in
[SECURITY.md](SECURITY.md). Public disclosure of vulnerabilities before a fix
is available is a serious Code of Conduct violation that may result in an
immediate temporary or permanent ban, depending on the severity and impact.

### 2. Malicious Contributions

Deliberately submitting code containing backdoors, security vulnerabilities,
data exfiltration mechanisms, logic bombs, or any other form of malicious
functionality will result in:

- Immediate permanent ban from all project spaces
- Removal of all pending and recent contributions by the individual
- Public disclosure of the incident (without identifying the reporter, if
  applicable)
- Reporting to relevant authorities if the action constitutes a criminal
  offense

### 3. Honest Representation

Contributors must not misrepresent the security properties of their
contributions. If a change has security implications — whether positive or
negative — they must be clearly documented in the pull request description.
This includes:

- Changes to input validation or sanitization logic
- Modifications to firewall command construction
- Alterations to file permission handling
- Updates to locking, cryptographic, or integrity verification mechanisms
- Introduction of new external inputs or trust boundaries

### 4. Security Review Cooperation

Contributors whose code is flagged during security review must cooperate in
good faith to address the concerns. Refusing to engage with legitimate
security feedback or attempting to merge code that bypasses security controls
is a Code of Conduct violation.

### 5. Responsible Testing

Contributors must not test the software in ways that affect systems or
networks they do not own or have explicit authorization to manage. Test suites
must use mock stubs and isolated environments — never live firewall operations
on shared or production systems.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Maintainer Responsibilities

Project maintainers are responsible for:

- Clarifying and enforcing the standards of acceptable behavior
- Taking appropriate and fair corrective action in response to any behavior
  they deem inappropriate, threatening, offensive, or harmful
- Removing, editing, or rejecting comments, commits, code, wiki edits, issues,
  and other contributions that are not aligned with this Code of Conduct
- Communicating reasons for moderation decisions when appropriate
- Applying enforcement consistently and impartially
- Recusing themselves from enforcement decisions involving people with whom
  they have a personal conflict of interest
- Maintaining the confidentiality of reporters
- Leading by example in all project interactions

Maintainers who do not follow or enforce the Code of Conduct in good faith may
face temporary or permanent consequences as determined by other members of the
project's leadership.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Attribution

This Code of Conduct is adapted from the
[Contributor Covenant](https://www.contributor-covenant.org/), version 2.1,
available at
[https://www.contributor-covenant.org/version/2/1/code_of_conduct.html](https://www.contributor-covenant.org/version/2/1/code_of_conduct.html).

Community Impact Guidelines were inspired by
[Mozilla's code of conduct enforcement ladder](https://github.com/mozilla/diversity).

The Responsible Use Policy, Security-Specific Provisions, Contributor Rights
and Responsibilities, Intellectual Property, and Appeal Process sections are
original additions specific to the Apotropaios project.

For answers to common questions about the Contributor Covenant, see the FAQ at
[https://www.contributor-covenant.org/faq](https://www.contributor-covenant.org/faq).

Translations are available at
[https://www.contributor-covenant.org/translations](https://www.contributor-covenant.org/translations).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>
