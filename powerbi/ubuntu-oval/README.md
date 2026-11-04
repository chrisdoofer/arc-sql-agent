# Public Ubuntu OVAL reference

Arc Insights v3.5.2 reads a prepared copy of Canonical's public USN OVAL data.
Report users do not need Python, a local JSON file, or a file-path parameter.

- Reference: <https://raw.githubusercontent.com/chrisdoofer/arc-sql-agent/refs/heads/ubuntu-oval-data/ubuntu-usn-oval.json>
- Publisher: [Publish Ubuntu OVAL reference](https://github.com/chrisdoofer/arc-sql-agent/actions/workflows/publish-ubuntu-oval.yaml)
- Official source: <https://security-metadata.canonical.com/oval/>

## Refresh and ownership

The workflow runs every six hours and can also be dispatched manually on `main`.
It prepares Ubuntu noble, jammy and focal, validates the result, and atomically
updates the JSON on the dedicated `ubuntu-oval-data` branch. It never writes to
the report or reads tenant data, customer inventory or Azure credentials.
Only the designated repository's `main` branch can publish.

The contents change as Canonical adds or revises advisories. The stable URL and
versioned schema separate these updates from report releases. A breaking schema
change needs coordinated publisher/reader changes; routine advisory updates do
not require a new template.

The reference contains `schema_version`, `generated_at`, `sources`, `notices` and
`cves`. Source manifests retain feed URLs, SHA-256 hashes, vendor generator
timestamps and unsupported-rule counts. `generated_at` records successful
retrieval/preparation, not the vendor's latest publication time.

A failed preparation or publication fails the workflow and leaves the previous
snapshot intact. The report rejects snapshots older than 24 hours, so the
repository maintainer must monitor failed or disabled scheduled runs. GitHub
Actions schedules are best-effort, not an availability guarantee. Restore the
publisher rather than disabling the report's freshness or privacy checks.

The data is an inferred advisory association, not a full OVAL evaluation or
proof that an installed machine is exploitable. The parser supports direct
positive binary-package constraints; unsupported tests/definitions are counted
and reported, not silently treated as matching packages.

## Maintainer commands

From the repository root:

```powershell
python -m unittest discover -s .\powerbi\ubuntu-oval\tests -v
node --test .\powerbi\ubuntu-oval\tests\test_publish_ubuntu_oval.js
python .\powerbi\ubuntu-oval\prepare_ubuntu_oval.py --output .\ubuntu-usn-oval.json
gh workflow run publish-ubuntu-oval.yaml --repo chrisdoofer/arc-sql-agent --ref main
```

Python uses only its standard library. The local preparation command is for
maintainers or private mirrors; report users should use the hosted reference.
Configure Anonymous authentication and organisation-appropriate privacy levels
for public web sources. No local-file gateway is needed for this reference;
other report sources can still have their own refresh requirements.
