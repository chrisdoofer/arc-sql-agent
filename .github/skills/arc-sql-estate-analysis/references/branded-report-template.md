# Branded report HTML template

Use this self-contained template when `/export-pdf` (or equivalent export prompt) is requested.

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>SQL Server Estate Analysis Report</title>
  <style>
    :root {
      --ms-blue-1: #0078d4;
      --ms-blue-2: #005a9e;
      --text: #1f2937;
      --muted: #6b7280;
      --border: #d1d5db;
      --bg: #f8fafc;
      --badge-green: #107c10;
      --badge-amber: #ffb900;
      --badge-red: #d13438;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Segoe UI", "Segoe UI Variable", Arial, sans-serif;
      color: var(--text);
      background: var(--bg);
    }
    .watermark {
      position: fixed;
      top: 45%;
      left: 20%;
      transform: rotate(-30deg);
      font-size: 56px;
      font-weight: 700;
      color: rgba(0, 0, 0, 0.06);
      z-index: 0;
      pointer-events: none;
      user-select: none;
    }
    .header {
      position: relative;
      z-index: 1;
      color: #fff;
      background: linear-gradient(90deg, var(--ms-blue-1), var(--ms-blue-2));
      padding: 20px 28px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .ms-wordmark {
      font-weight: 600;
      letter-spacing: 0.2px;
      font-size: 20px;
    }
    .arc-badge {
      border: 1px solid rgba(255, 255, 255, 0.5);
      border-radius: 999px;
      padding: 6px 12px;
      font-size: 12px;
      line-height: 1;
      white-space: nowrap;
      background: rgba(255, 255, 255, 0.12);
    }
    main {
      position: relative;
      z-index: 1;
      max-width: 1100px;
      margin: 16px auto 40px;
      padding: 0 20px;
    }
    section {
      background: #fff;
      border: 1px solid var(--border);
      border-radius: 8px;
      margin: 14px 0;
      padding: 18px;
      page-break-inside: avoid;
    }
    h1 { margin: 0; font-size: 24px; }
    h2 { margin: 0 0 12px; font-size: 18px; }
    .meta {
      color: var(--muted);
      font-size: 12px;
      margin-top: 6px;
    }
    .badge {
      display: inline-block;
      border-radius: 999px;
      padding: 2px 10px;
      color: #fff;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.3px;
      vertical-align: middle;
    }
    .badge.green { background: var(--badge-green); }
    .badge.amber { background: #7f4f00; color: var(--badge-amber); border: 1px solid var(--badge-amber); }
    .badge.red { background: var(--badge-red); }
    footer {
      position: fixed;
      left: 0;
      right: 0;
      bottom: 0;
      border-top: 1px solid var(--border);
      background: #fff;
      color: var(--muted);
      font-size: 12px;
      padding: 6px 20px;
      display: flex;
      justify-content: space-between;
    }
  </style>
</head>
<body>
  <div class="watermark">Confidential</div>
  <header class="header">
    <div class="brand">
      <svg width="24" height="24" viewBox="0 0 24 24" role="img" aria-label="Microsoft logo" xmlns="http://www.w3.org/2000/svg">
        <rect x="0" y="0" width="11" height="11" fill="#f25022" />
        <rect x="13" y="0" width="11" height="11" fill="#7fba00" />
        <rect x="0" y="13" width="11" height="11" fill="#00a4ef" />
        <rect x="13" y="13" width="11" height="11" fill="#ffb900" />
      </svg>
      <span class="ms-wordmark">Microsoft</span>
    </div>
    <div class="arc-badge">Azure Arc · SQL Server Estate Analysis</div>
  </header>

  <main>
    <section>
      <h1>SQL Server Estate Analysis Report</h1>
      <div class="meta">Generated: {{generationDate}}</div>
    </section>

    <section><h2>Executive Summary</h2>{{executiveSummaryHtml}}</section>
    <section><h2>Estate summary</h2>{{estateSummaryHtml}}</section>
    <section><h2>Key optimisation opportunities</h2>{{keyOptimisationsHtml}}</section>
    <section><h2>Enterprise downgrade audit</h2>{{enterpriseDowngradeAuditHtml}}</section>
    <section><h2>Quick wins</h2>{{quickWinsHtml}}</section>
    <section><h2>Strategic moves</h2>{{strategicMovesHtml}}</section>
    <section><h2>Azure target recommendations</h2>{{azureTargetsHtml}}</section>
    <section><h2>Risks and blockers</h2>{{risksHtml}}</section>
    <section><h2>Data gaps / follow-up questions</h2>{{dataGapsHtml}}</section>
  </main>

  <footer>
    <span>Confidential</span>
    <span>Generated {{generationDate}}</span>
  </footer>
</body>
</html>
```

Badge usage for readiness states:

- GREEN: `<span class="badge green">GREEN</span>`
- AMBER: `<span class="badge amber">AMBER</span>`
- RED: `<span class="badge red">RED</span>`
