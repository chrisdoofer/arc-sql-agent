const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const workflow = fs.readFileSync(
  path.resolve(__dirname, '../../../.github/workflows/publish-ubuntu-oval.yaml'),
  'utf8'
).replace(/\r\n/g, '\n');
const script = workflow.split('          script: |\n')[1]
  .split('\n').map(line => line.slice(12)).join('\n');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const publish = new AsyncFunction('github', 'context', 'core', 'require', 'process', script);

function fixture() {
  const document = {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    notices: { noble: [{}], jammy: [{}], focal: [{}] },
    sources: ['noble', 'jammy', 'focal'].map(release => ({ release })),
    cves: { 'CVE-2026-58015': { cvss_score: 5.9 } }
  };
  const calls = [];
  const github = {
    rest: {
      git: {
        getRef: async args => {
          calls.push(['getRef', args]);
          return { data: { object: { sha: 'main-sha' } } };
        },
        createRef: async args => { calls.push(['createRef', args]); }
      },
      repos: {
        getContent: async args => {
          calls.push(['getContent', args]);
          return { data: { type: 'file', sha: 'previous-sha' } };
        },
        createOrUpdateFileContents: async args => { calls.push(['update', args]); }
      }
    }
  };
  const summary = {};
  for (const method of ['addHeading', 'addRaw', 'addLink', 'write']) {
    summary[method] = () => summary;
  }
  return {
    document, calls, github,
    run: () => publish(
      github, { repo: { owner: 'chrisdoofer', repo: 'arc-sql-agent' } },
      { summary },
      name => {
        assert.equal(name, 'fs');
        return {
          readFileSync: filename => {
            assert.equal(filename, 'prepared.json');
            return Buffer.from(JSON.stringify(document));
          }
        };
      },
      { env: { SNAPSHOT_PATH: 'prepared.json' } }
    )
  };
}

test('updates only the reference branch, with the previous SHA', async () => {
  const f = fixture();
  await f.run();
  const update = f.calls.find(([operation]) => operation === 'update')[1];
  assert.equal(update.branch, 'ubuntu-oval-data');
  assert.equal(update.path, 'ubuntu-usn-oval.json');
  assert.equal(update.sha, 'previous-sha');
  assert.deepEqual(JSON.parse(Buffer.from(update.content, 'base64')), f.document);
  assert.equal(f.calls.filter(([operation]) => operation === 'update').length, 1);
});

test('bootstraps a missing branch from main and creates the first reference', async () => {
  const f = fixture();
  f.github.rest.git.getRef = async args => {
    f.calls.push(['getRef', args]);
    if (args.ref === 'heads/ubuntu-oval-data') throw { status: 404 };
    assert.equal(args.ref, 'heads/main');
    return { data: { object: { sha: 'main-sha' } } };
  };
  f.github.rest.repos.getContent = async () => { throw { status: 404 }; };
  await f.run();
  assert.deepEqual(f.calls.find(([op]) => op === 'createRef')[1], {
    owner: 'chrisdoofer', repo: 'arc-sql-agent',
    ref: 'refs/heads/ubuntu-oval-data', sha: 'main-sha'
  });
  assert.equal(f.calls.find(([op]) => op === 'update')[1].sha, undefined);
});

for (const [name, mutate] of [
  ['stale', d => { d.generated_at = new Date(Date.now() - 7200000).toISOString(); }],
  ['future', d => { d.generated_at = new Date(Date.now() + 7200000).toISOString(); }],
  ['invalid timestamp', d => { d.generated_at = 'invalid'; }],
  ['wrong schema', d => { d.schema_version = 2; }],
  ['missing release', d => { delete d.notices.jammy; }],
  ['empty release', d => { d.notices.focal = []; }],
  ['duplicate manifest', d => { d.sources.push({ release: 'noble' }); }],
  ['empty CVE dictionary', d => { d.cves = {}; }]
]) {
  test(`rejects ${name} without changing the last published reference`, async () => {
    const f = fixture();
    mutate(f.document);
    await assert.rejects(f.run, /invalid or stale/);
    assert.deepEqual(f.calls, []);
  });
}

test('does not mistake a permissions error for a missing branch', async () => {
  const f = fixture();
  f.github.rest.git.getRef = async () => { throw { status: 403 }; };
  await assert.rejects(f.run, error => error.status === 403);
  assert.equal(f.calls.length, 0);
});

test('does not replace a directory or swallow a content lookup failure', async () => {
  for (const status of [null, 503]) {
    const f = fixture();
    f.github.rest.repos.getContent = async () => {
      if (status) throw { status };
      return { data: [] };
    };
    await assert.rejects(f.run);
    assert.equal(f.calls.some(([op]) => op === 'update'), false);
  }
});

test('surfaces a concurrent publication conflict instead of overwriting it', async () => {
  const f = fixture();
  f.github.rest.repos.createOrUpdateFileContents = async () => { throw { status: 409 }; };
  await assert.rejects(f.run, error => error.status === 409);
});

test('scheduled publishing is restricted to the canonical main branch', () => {
  assert.match(workflow, /cron: '23 \*\/6 \* \* \*'/);
  assert.match(workflow, /github\.repository == 'chrisdoofer\/arc-sql-agent' && github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /persist-credentials: false/);
  assert.match(workflow, /cancel-in-progress: false/);
  assert.doesNotMatch(workflow, /pull_request_target/);
});
