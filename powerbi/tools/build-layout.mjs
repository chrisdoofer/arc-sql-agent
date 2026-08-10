import crypto from "node:crypto";
import fs from "node:fs";

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error(
    "Usage: node build-layout.mjs <input-layout> <output-layout> <project-path>",
  );
}

const generatedPages = [
  {
    name: "7f3d6cf2b1a64e1f9a01",
    displayName: "Security Patching CVE Audit",
  },
  {
    name: "c1424e478c6a4d168b02",
    displayName: "Best Practices",
  },
  {
    name: "ab568abcf57d47f68c03",
    displayName: "DMV Audit",
  },
];

const layout = JSON.parse(
  fs.readFileSync(inputPath, "utf16le").replace(/^\uFEFF/, ""),
);
const sqlSource = layout.sections.find(
  (section) => section.displayName === "SQL Instances",
);
const extensionSource = layout.sections.find(
  (section) => section.displayName === "Extensions",
);
if (!sqlSource || !extensionSource) {
  throw new Error("Required SQL Instances or Extensions page not found");
}

function getConfig(visual) {
  return JSON.parse(visual.config);
}

function getTabOrder(visual) {
  return getConfig(visual).layouts?.[0]?.position?.tabOrder ?? visual.tabOrder;
}

function findVisual(page, tabOrder) {
  const visual = page.visualContainers.find(
    (candidate) => getTabOrder(candidate) === tabOrder,
  );
  if (!visual) {
    throw new Error(
      `Visual with tab order ${tabOrder} not found on ${page.displayName}`,
    );
  }
  return visual;
}

function replaceExact(value, replacements) {
  if (Array.isArray(value)) {
    return value.map((item) => replaceExact(item, replacements));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [
        key,
        replaceExact(item, replacements),
      ]),
    );
  }
  if (typeof value === "string" && Object.hasOwn(replacements, value)) {
    return replacements[value];
  }
  return value;
}

function updateVisual(page, tabOrder, replacements) {
  const visual = findVisual(page, tabOrder);
  for (const property of ["config", "query", "dataTransforms"]) {
    if (!visual[property]) {
      continue;
    }
    visual[property] = JSON.stringify(
      replaceExact(JSON.parse(visual[property]), replacements),
    );
  }
}

function setMeasureMetadata(page, tabOrder, labels, formats = []) {
  const visual = findVisual(page, tabOrder);
  const config = getConfig(visual);
  const prototypeMeasures = (
    config.singleVisual?.prototypeQuery?.Select ?? []
  ).filter((item) => item.Measure);
  prototypeMeasures.forEach((item, index) => {
    if (labels[index]) {
      item.NativeReferenceName = labels[index];
    }
  });

  if (visual.query) {
    const query = JSON.parse(visual.query);
    const measures = (
      query.Commands?.[0]?.SemanticQueryDataShapeCommand?.Query?.Select ?? []
    ).filter((item) => item.Measure);
    measures.forEach((item, index) => {
      if (labels[index]) {
        item.NativeReferenceName = labels[index];
      }
    });
    visual.query = JSON.stringify(query);
  }

  const transforms = visual.dataTransforms
    ? JSON.parse(visual.dataTransforms)
    : null;
  if (transforms) {
    (transforms.queryMetadata?.Select ?? []).forEach((item, index) => {
      if (labels[index]) {
        item.Restatement = labels[index];
      }
      if (formats[index]) {
        item.Format = formats[index];
      }
    });
    const selects = (transforms.selects ?? []).filter(
      (item) => item.expr?.Measure,
    );
    selects.forEach((item, index) => {
      if (labels[index]) {
        item.displayName = labels[index];
      }
      if (formats[index]) {
        item.format = formats[index];
      }
    });

    const referenceTitles = transforms.objects?.referenceLabelTitle ?? [];
    const referenceValues = transforms.objects?.referenceLabel ?? [];
    selects.slice(1).forEach((item, index) => {
      const id = item.relatedObjects?.referenceLabel?.value?.[0]?.id;
      const title = referenceTitles.find(
        (entry) => entry.selector?.id === id,
      );
      if (title && labels[index + 1]) {
        title.properties.titleContentType = {
          expr: { Literal: { Value: "'custom'" } },
        };
        title.properties.titleText = {
          expr: { Literal: { Value: `'${labels[index + 1]}'` } },
        };
      }
      const value = referenceValues.find(
        (entry) => entry.selector?.id === id,
      );
      if (value && formats[index + 1]) {
        value.properties.formatString = {
          expr: { Literal: { Value: `'${formats[index + 1]}'` } },
        };
      }
    });
    visual.dataTransforms = JSON.stringify(transforms);
  }

  const blankDisplay = formats[0]?.includes("%") ? "0.0%" : "0";
  for (const valueObject of config.singleVisual?.objects?.value ?? []) {
    if (valueObject.properties?.showBlankAs) {
      valueObject.properties.showBlankAs = {
        expr: { Literal: { Value: `'${blankDisplay}'` } },
      };
    }
  }

  const measureSelects = (transforms?.selects ?? []).filter(
    (item) => item.expr?.Measure,
  );
  const configReferenceTitles =
    config.singleVisual?.objects?.referenceLabelTitle ?? [];
  measureSelects.slice(1).forEach((item, index) => {
    const id = item.relatedObjects?.referenceLabel?.value?.[0]?.id;
    const title = configReferenceTitles.find(
      (entry) => entry.selector?.id === id,
    );
    if (title && labels[index + 1]) {
      title.properties.titleContentType = {
        expr: { Literal: { Value: "'custom'" } },
      };
      title.properties.titleText = {
        expr: { Literal: { Value: `'${labels[index + 1]}'` } },
      };
    }
  });

  config.singleVisual.columnProperties = {};
  measureSelects.forEach((item, index) => {
    if (item.queryName) {
      config.singleVisual.columnProperties[item.queryName] = {
        ...(labels[index] ? { displayName: labels[index] } : {}),
        ...(formats[index] ? { formatString: formats[index] } : {}),
      };
    }
  });
  visual.config = JSON.stringify(config);
}

function compactKpiCard(page, tabOrder, primaryMeasure) {
  const visual = findVisual(page, tabOrder);
  const config = getConfig(visual);
  const transforms = visual.dataTransforms
    ? JSON.parse(visual.dataTransforms)
    : null;

  for (const objects of [
    config.singleVisual?.objects,
    transforms?.objects,
  ].filter(Boolean)) {
    const defaultValue = (objects.value ?? []).find(
      (entry) => entry.selector?.id === "default",
    );
    if (defaultValue) {
      defaultValue.properties.fontSize = {
        expr: { Literal: { Value: "13D" } },
      };
    }

    const defaultLabel = (objects.label ?? []).find(
      (entry) => entry.selector?.id === "default",
    );
    if (defaultLabel) {
      defaultLabel.properties.fontSize = {
        expr: { Literal: { Value: "9D" } },
      };
    }

    const padding = (objects.padding ?? []).find(
      (entry) => entry.selector?.id === "default",
    );
    if (padding) {
      Object.assign(padding.properties, {
        paddingUniform: { expr: { Literal: { Value: "2L" } } },
        paddingIndividual: { expr: { Literal: { Value: "true" } } },
        topMargin: { expr: { Literal: { Value: "0L" } } },
        bottomMargin: { expr: { Literal: { Value: "0L" } } },
        leftMargin: { expr: { Literal: { Value: "6L" } } },
        rightMargin: { expr: { Literal: { Value: "6L" } } },
      });
    }

    let layout = (objects.layout ?? []).find(
      (entry) => entry.selector?.id === "default",
    );
    if (!layout) {
      layout = { properties: {}, selector: { id: "default" } };
      (objects.layout ??= []).push(layout);
    }
    layout.properties.calloutSize = {
      expr: { Literal: { Value: "60D" } },
    };

    const referenceLabels = (objects.referenceLabel ?? []).filter(
      (entry) => entry.selector?.metadata === primaryMeasure,
    );
    objects.referenceLabelValue ??= [];
    objects.referenceLabelTitle ??= [];
    for (const referenceLabel of referenceLabels) {
      const selector = {
        metadata: referenceLabel.selector.metadata,
        id: referenceLabel.selector.id,
      };
      objects.referenceLabelValue.push({
        properties: {
          valueFontSize: { expr: { Literal: { Value: "9D" } } },
        },
        selector,
      });
      objects.referenceLabelTitle.push({
        properties: {
          titleFontSize: { expr: { Literal: { Value: "8D" } } },
        },
        selector,
      });
    }
  }

  visual.config = JSON.stringify(config);
  if (transforms) {
    visual.dataTransforms = JSON.stringify(transforms);
  }
}

function updateTextbox(page, tabOrder, text) {
  const visual = findVisual(page, tabOrder);
  const config = getConfig(visual);
  const runs =
    config.singleVisual?.objects?.general?.[0]?.properties?.paragraphs?.flatMap(
      (paragraph) => paragraph.textRuns ?? [],
    ) ?? [];
  if (runs.length === 0) {
    throw new Error(`Textbox ${tabOrder} has no text run`);
  }
  runs[0].value = text;
  for (const run of runs.slice(1)) {
    run.value = "";
  }
  visual.config = JSON.stringify(config);
}

function setPosition(visual, position) {
  Object.assign(visual, position);
  visual.tabOrder = position.tabOrder;
  const config = getConfig(visual);
  Object.assign(config.layouts[0].position, position);
  visual.config = JSON.stringify(config);
}

function cloneVisual(page, sourceTabOrder, tabOrder, position) {
  const visual = structuredClone(findVisual(page, sourceTabOrder));
  setPosition(visual, { ...position, tabOrder });
  delete visual.query;
  delete visual.dataTransforms;
  const config = getConfig(visual);
  config.name = crypto
    .createHash("sha256")
    .update(`${page.name}:${config.name}:${tabOrder}`)
    .digest("hex")
    .slice(0, 20);
  visual.config = JSON.stringify(config);
  page.visualContainers.push(visual);
  return visual;
}

function replaceVisual(visual, replacements) {
  for (const property of ["config", "query", "dataTransforms"]) {
    if (!visual[property]) {
      continue;
    }
    visual[property] = JSON.stringify(
      replaceExact(JSON.parse(visual[property]), replacements),
    );
  }
}

function stampVisualName(visual, page, tabOrder) {
  const config = getConfig(visual);
  config.name = crypto
    .createHash("sha256")
    .update(`${page.name}:${config.name}:${tabOrder}`)
    .digest("hex")
    .slice(0, 20);
  visual.config = JSON.stringify(config);
}

function columnSelect(alias, table, column, label) {
  return {
    Column: {
      Expression: {
        SourceRef: {
          Source: alias,
        },
      },
      Property: column,
    },
    Name: `${table}.${column}`,
    NativeReferenceName: label,
  };
}

function measureSelect(alias, table, measure, label) {
  return {
    Measure: {
      Expression: {
        SourceRef: {
          Source: alias,
        },
      },
      Property: measure,
    },
    Name: `${table}.${measure}`,
    NativeReferenceName: label,
  };
}

function transformColumn(table, column, label, dataType = "string") {
  return {
    displayName: label,
    queryName: `${table}.${column}`,
    roles: { Values: true },
    type: {
      category: null,
      underlyingType: dataType === "datetime" ? 7 : 1,
    },
    expr: {
      Column: {
        Expression: {
          SourceRef: {
            Entity: table,
          },
        },
        Property: column,
      },
    },
  };
}

function transformMeasure(table, measure, label, role = "Y") {
  return {
    displayName: label,
    format: "#,##0",
    queryName: `${table}.${measure}`,
    roles: { [role]: true },
    type: {
      category: null,
      underlyingType: 260,
    },
    expr: {
      Measure: {
        Expression: {
          SourceRef: {
            Entity: table,
          },
        },
        Property: measure,
      },
    },
  };
}

function bindTable(visual, table, columns, sortColumn = columns[0]?.column) {
  const config = getConfig(visual);
  const tables = [...new Set(columns.map((item) => item.table ?? table))];
  const sourceNames = new Map(
    tables.map((entity, index) => [entity, index === 0 ? "t" : `t${index}`]),
  );
  const selects = columns.map((item) => {
    const entity = item.table ?? table;
    return columnSelect(sourceNames.get(entity), entity, item.column, item.label);
  });
  const sortItem = columns.find(
    (item) => item.column === sortColumn && (item.table ?? table) === table,
  );
  const query = {
    Commands: [
      {
        SemanticQueryDataShapeCommand: {
          Query: {
            Version: 2,
            From: tables.map((entity) => ({
              Name: sourceNames.get(entity),
              Entity: entity,
              Type: 0,
            })),
            Select: selects,
            ...(sortItem
              ? {
                  OrderBy: [
                    {
                      Direction: 1,
                      Expression: {
                        Column: {
                          Expression: {
                            SourceRef: { Source: sourceNames.get(table) },
                          },
                          Property: sortColumn,
                        },
                      },
                    },
                  ],
                }
              : {}),
          },
          Binding: {
            Primary: {
              Groupings: [
                {
                  Projections: columns.map((_, index) => index),
                },
              ],
            },
            DataReduction: {
              DataVolume: 6,
              Primary: {
                Window: {
                  Count: 500,
                },
              },
            },
            Version: 1,
          },
          ExecutionMetricsKind: 1,
        },
      },
    ],
  };

  config.singleVisual.projections = {
    Values: columns.map((item) => ({
      queryRef: `${item.table ?? table}.${item.column}`,
    })),
  };
  config.singleVisual.prototypeQuery = query.Commands[0].SemanticQueryDataShapeCommand.Query;
  config.singleVisual.columnProperties = Object.fromEntries(
    columns.map((item) => [
      `${item.table ?? table}.${item.column}`,
      { displayName: item.label },
    ]),
  );
  config.singleVisual.objects ??= {};
  config.singleVisual.objects.columnHeaders ??= [{}];
  config.singleVisual.objects.columnHeaders[0].properties ??= {};
  config.singleVisual.objects.columnHeaders[0].properties.autoSizeColumnWidth = {
    expr: { Literal: { Value: "true" } },
  };
  config.singleVisual.objects.columnHeaders[0].properties.columnAdjustment = {
    expr: { Literal: { Value: "'growToFit'" } },
  };
  visual.config = JSON.stringify(config);
  visual.query = JSON.stringify(query);

  const transforms = visual.dataTransforms
    ? JSON.parse(visual.dataTransforms)
    : {};
  transforms.objects = {};
  transforms.visualElements = [];
  transforms.projectionOrdering = {
    Values: columns.map((_, index) => index),
  };
  transforms.queryMetadata = {
    Select: columns.map((item) => ({
      Restatement: item.label,
      Name: `${item.table ?? table}.${item.column}`,
      Type: item.dataType === "datetime" ? 7 : 2048,
    })),
  };
  transforms.selects = columns.map((item) =>
    transformColumn(
      item.table ?? table,
      item.column,
      item.label,
      item.dataType,
    ),
  );
  visual.dataTransforms = JSON.stringify(transforms);
}

function bindCategoryMeasure(
  visual,
  table,
  category,
  categoryLabel,
  measure,
  measureLabel,
) {
  const config = getConfig(visual);
  const query = {
    Commands: [
      {
        SemanticQueryDataShapeCommand: {
          Query: {
            Version: 2,
            From: [
              { Name: "t", Entity: table, Type: 0 },
              { Name: "a", Entity: "all_measures", Type: 0 },
            ],
            Select: [
              columnSelect("t", table, category, categoryLabel),
              measureSelect("a", "all_measures", measure, measureLabel),
            ],
            OrderBy: [
              {
                Direction: 2,
                Expression: {
                  Measure: {
                    Expression: {
                      SourceRef: { Source: "a" },
                    },
                    Property: measure,
                  },
                },
              },
            ],
          },
          Binding: {
            Primary: {
              Groupings: [{ Projections: [0, 1] }],
            },
            DataReduction: {
              DataVolume: 4,
              Primary: {
                Window: {
                  Count: 1000,
                },
              },
            },
            Version: 1,
          },
          ExecutionMetricsKind: 1,
        },
      },
    ],
  };

  config.singleVisual.projections = {
    Category: [
      {
        queryRef: `${table}.${category}`,
        active: true,
      },
    ],
    Y: [
      {
        queryRef: `all_measures.${measure}`,
      },
    ],
  };
  config.singleVisual.prototypeQuery = query.Commands[0].SemanticQueryDataShapeCommand.Query;
  config.singleVisual.columnProperties = {
    [`${table}.${category}`]: { displayName: categoryLabel },
    [`all_measures.${measure}`]: {
      displayName: measureLabel,
      formatString: "#,##0",
    },
  };
  visual.config = JSON.stringify(config);
  visual.query = JSON.stringify(query);

  const transforms = visual.dataTransforms
    ? JSON.parse(visual.dataTransforms)
    : {};
  transforms.objects = {};
  transforms.visualElements = [];
  transforms.projectionOrdering = {
    Category: [0],
    Y: [1],
  };
  transforms.queryMetadata = {
    Select: [
      {
        Restatement: categoryLabel,
        Name: `${table}.${category}`,
        Type: 2048,
      },
      {
        Restatement: measureLabel,
        Name: `all_measures.${measure}`,
        Type: 1,
        Format: "#,##0",
      },
    ],
  };
  transforms.selects = [
    {
      ...transformColumn(table, category, categoryLabel),
      roles: { Category: true },
    },
    transformMeasure("all_measures", measure, measureLabel),
  ];
  visual.dataTransforms = JSON.stringify(transforms);
}

function showDonutMetrics(visual) {
  const config = getConfig(visual);
  const objects = (config.singleVisual.objects ??= {});
  objects.legend = [
    {
      properties: {
        show: { expr: { Literal: { Value: "true" } } },
        position: { expr: { Literal: { Value: "'RightCenter'" } } },
        showTitle: { expr: { Literal: { Value: "false" } } },
        fontSize: { expr: { Literal: { Value: "8D" } } },
        labelColor: {
          solid: {
            color: { expr: { Literal: { Value: "'#FFFFFF'" } } },
          },
        },
      },
    },
  ];
  objects.labels = [
    {
      properties: {
        show: { expr: { Literal: { Value: "true" } } },
        labelStyle: { expr: { Literal: { Value: "'Data'" } } },
        position: { expr: { Literal: { Value: "'inside'" } } },
        fontSize: { expr: { Literal: { Value: "8D" } } },
        labelPrecision: { expr: { Literal: { Value: "0L" } } },
        color: {
          solid: {
            color: { expr: { Literal: { Value: "'#FFFFFF'" } } },
          },
        },
      },
    },
  ];
  objects.slices = [
    {
      properties: {
        innerRadiusRatio: { expr: { Literal: { Value: "65L" } } },
      },
    },
  ];
  visual.config = JSON.stringify(config);
}

function showBarMetrics(visual) {
  const config = getConfig(visual);
  const objects = (config.singleVisual.objects ??= {});
  const labels = (objects.labels ??= [{ properties: {} }]);
  labels[0].properties ??= {};
  Object.assign(labels[0].properties, {
    show: { expr: { Literal: { Value: "true" } } },
    enableValueDataLabel: { expr: { Literal: { Value: "true" } } },
    labelPosition: { expr: { Literal: { Value: "'InsideEnd'" } } },
    labelOverflow: { expr: { Literal: { Value: "true" } } },
    fontSize: { expr: { Literal: { Value: "8D" } } },
    bold: { expr: { Literal: { Value: "true" } } },
    labelPrecision: { expr: { Literal: { Value: "0L" } } },
    color: {
      solid: {
        color: { expr: { Literal: { Value: "'#FFFFFF'" } } },
      },
    },
  });
  visual.config = JSON.stringify(config);
}

function clearPageToChrome(page, retainedTabOrders = []) {
  const retained = new Set(retainedTabOrders);
  page.visualContainers = page.visualContainers.filter((visual) => {
    const config = getConfig(visual);
    const position = config.layouts?.[0]?.position ?? {};
    const visualType = config.singleVisual?.visualType;
    return (
      position.y < 55 ||
      visualType === "actionButton" ||
      retained.has(getTabOrder(visual))
    );
  });
}

function addPanel(page, templates, tabOrder, position, title) {
  const shape = structuredClone(templates.shape);
  setPosition(shape, { ...position, tabOrder });
  const shapeConfig = getConfig(shape);
  shapeConfig.name = crypto
    .createHash("sha256")
    .update(`${page.name}:panel:${tabOrder}`)
    .digest("hex")
    .slice(0, 20);
  shape.config = JSON.stringify(shapeConfig);
  page.visualContainers.push(shape);

  const heading = structuredClone(templates.heading);
  setPosition(heading, {
    x: position.x + 12,
    y: position.y + 6,
    z: tabOrder + 1,
    width: position.width - 24,
    height: 28,
    tabOrder: tabOrder + 1,
  });
  const headingConfig = getConfig(heading);
  headingConfig.name = crypto
    .createHash("sha256")
    .update(`${page.name}:heading:${tabOrder}`)
    .digest("hex")
    .slice(0, 20);
  heading.config = JSON.stringify(headingConfig);
  setTextboxParagraphs(heading, [title], "10pt");
  page.visualContainers.push(heading);
}

function setTextboxParagraphs(visual, paragraphs, fontSize = "10pt") {
  const config = getConfig(visual);
  config.singleVisual.objects.general[0].properties.paragraphs = paragraphs.map(
    (text) => ({
      textRuns: [
        {
          value: text,
          textStyle: {
            fontSize,
            color: "#ffffff",
          },
        },
      ],
    }),
  );
  visual.config = JSON.stringify(config);
}

function finalizePage(page, pageDefinition, ordinal) {
  page.name = pageDefinition.name;
  page.displayName = pageDefinition.displayName;
  page.ordinal = ordinal;
  const visualNameMap = Object.fromEntries(
    page.visualContainers.map((visual) => {
      const originalName = getConfig(visual).name;
      return [
        originalName,
        crypto
          .createHash("sha256")
          .update(`${page.name}:${originalName}`)
          .digest("hex")
          .slice(0, 20),
      ];
    }),
  );
  for (const visual of page.visualContainers) {
    for (const property of ["config", "query", "dataTransforms"]) {
      if (visual[property]) {
        visual[property] = JSON.stringify(
          replaceExact(JSON.parse(visual[property]), visualNameMap),
        );
      }
    }
  }
  return page;
}

function buildSecurityPage() {
  const page = structuredClone(sqlSource);
  const templates = {
    shape: structuredClone(findVisual(page, 1000)),
    heading: structuredClone(findVisual(page, 7000)),
    card: structuredClone(findVisual(page, 28000)),
    bar: structuredClone(findVisual(page, 0)),
    donut: structuredClone(findVisual(page, 13000)),
    table: structuredClone(findVisual(page, 32000)),
  };
  clearPageToChrome(page, [5000, 20000, 23000]);
  updateTextbox(page, 5000, "Arc Jumpstart | Security");
  updateTextbox(page, 20000, "Security / Patching / CVE Audit");

  const patchCard = structuredClone(templates.card);
  setPosition(patchCard, {
    x: 16,
    y: 60,
    z: 50000,
    width: 600,
    height: 104,
    tabOrder: 50000,
  });
  stampVisualName(patchCard, page, 50000);
  replaceVisual(patchCard, {
    kpi_azure_sql_instance_count: "kpi_patch_assessed_machine_count",
    "all_measures.kpi_azure_sql_instance_count":
      "all_measures.kpi_patch_assessed_machine_count",
    kpi_azure_sql_cores: "kpi_missing_patch_count",
    "all_measures.kpi_azure_sql_cores":
      "all_measures.kpi_missing_patch_count",
    kpi_azure_sql_memory: "kpi_missing_security_patch_count",
    "all_measures.kpi_azure_sql_memory":
      "all_measures.kpi_missing_security_patch_count",
  });
  page.visualContainers.push(patchCard);
  setMeasureMetadata(
    page,
    50000,
    ["Assessed machines", "Missing patches", "Security patches"],
    ["#,##0", "#,##0", "#,##0"],
  );
  compactKpiCard(
    page,
    50000,
    "all_measures.kpi_patch_assessed_machine_count",
  );

  const cveCard = structuredClone(templates.card);
  setPosition(cveCard, {
    x: 630,
    y: 60,
    z: 51000,
    width: 606,
    height: 104,
    tabOrder: 51000,
  });
  stampVisualName(cveCard, page, 51000);
  replaceVisual(cveCard, {
    kpi_azure_sql_instance_count: "kpi_mapped_cve_count",
    "all_measures.kpi_azure_sql_instance_count":
      "all_measures.kpi_mapped_cve_count",
    kpi_azure_sql_cores: "kpi_cve_affected_machine_count",
    "all_measures.kpi_azure_sql_cores":
      "all_measures.kpi_cve_affected_machine_count",
    kpi_azure_sql_memory: "kpi_missing_critical_patch_count",
    "all_measures.kpi_azure_sql_memory":
      "all_measures.kpi_missing_critical_patch_count",
  });
  page.visualContainers.push(cveCard);
  setMeasureMetadata(
    page,
    51000,
    ["Mapped CVEs", "Affected machines", "Critical patches"],
    ["#,##0", "#,##0", "#,##0"],
  );
  compactKpiCard(page, 51000, "all_measures.kpi_mapped_cve_count");

  addPanel(
    page,
    templates,
    52000,
    { x: 16, y: 174, z: 52000, width: 390, height: 208 },
    "Missing patches by machine",
  );
  const machineChart = structuredClone(templates.bar);
  setPosition(machineChart, {
    x: 28,
    y: 206,
    z: 52002,
    width: 366,
    height: 164,
    tabOrder: 52002,
  });
  stampVisualName(machineChart, page, 52002);
  bindCategoryMeasure(
    machineChart,
    "fact_resources",
    "resource_name",
    "Machine",
    "kpi_missing_patch_count",
    "Missing patches",
  );
  showBarMetrics(machineChart);
  page.visualContainers.push(machineChart);

  addPanel(
    page,
    templates,
    53000,
    { x: 420, y: 174, z: 53000, width: 390, height: 208 },
    "Patch classification",
  );
  const classificationChart = structuredClone(templates.donut);
  setPosition(classificationChart, {
    x: 432,
    y: 206,
    z: 53002,
    width: 366,
    height: 164,
    tabOrder: 53002,
  });
  stampVisualName(classificationChart, page, 53002);
  bindCategoryMeasure(
    classificationChart,
    "view_missing_patches",
    "classification",
    "Classification",
    "kpi_missing_patch_count",
    "Missing patches",
  );
  showDonutMetrics(classificationChart);
  page.visualContainers.push(classificationChart);

  addPanel(
    page,
    templates,
    54000,
    { x: 824, y: 174, z: 54000, width: 412, height: 208 },
    "Mapped CVEs by severity",
  );
  const severityChart = structuredClone(templates.donut);
  setPosition(severityChart, {
    x: 836,
    y: 206,
    z: 54002,
    width: 388,
    height: 164,
    tabOrder: 54002,
  });
  stampVisualName(severityChart, page, 54002);
  bindCategoryMeasure(
    severityChart,
    "view_patch_cve_mappings",
    "severity",
    "Severity",
    "kpi_mapped_cve_count",
    "Mapped CVEs",
  );
  showDonutMetrics(severityChart);
  page.visualContainers.push(severityChart);

  addPanel(
    page,
    templates,
    55000,
    { x: 16, y: 394, z: 55000, width: 600, height: 350 },
    "All missing patches",
  );
  const patchTable = structuredClone(templates.table);
  setPosition(patchTable, {
    x: 28,
    y: 426,
    z: 55002,
    width: 576,
    height: 306,
    tabOrder: 55002,
  });
  stampVisualName(patchTable, page, 55002);
  bindTable(patchTable, "view_missing_patches", [
    { column: "machine_name", label: "Machine" },
    { column: "patch_name", label: "Missing patch" },
    { table: "dim_patch_kb", column: "kb_numeric", label: "KB" },
    { column: "classification", label: "Classification" },
    { column: "package_version", label: "Version" },
    { column: "reboot_behavior", label: "Reboot" },
    { column: "assessment_time", label: "Assessed", dataType: "datetime" },
  ]);
  page.visualContainers.push(patchTable);

  addPanel(
    page,
    templates,
    56000,
    { x: 630, y: 394, z: 56000, width: 606, height: 350 },
    "CVE and machine exposure",
  );
  const cveTable = structuredClone(templates.table);
  setPosition(cveTable, {
    x: 642,
    y: 426,
    z: 56002,
    width: 582,
    height: 306,
    tabOrder: 56002,
  });
  stampVisualName(cveTable, page, 56002);
  bindTable(cveTable, "view_patch_cve_mappings", [
    { column: "cve_id", label: "CVE" },
    { table: "dim_patch_kb", column: "kb_numeric", label: "KB" },
    { column: "machine_name", label: "Machine" },
    { column: "severity", label: "Severity" },
    { column: "product", label: "Vulnerability" },
    { column: "confidence", label: "Confidence" },
    { column: "mapping_source", label: "Source" },
  ]);
  page.visualContainers.push(cveTable);

  return finalizePage(page, generatedPages[0], 5);
}

function buildBestPracticesPage() {
  const page = structuredClone(sqlSource);
  const templates = {
    shape: structuredClone(findVisual(page, 1000)),
    heading: structuredClone(findVisual(page, 7000)),
    card: structuredClone(findVisual(page, 28000)),
    bar: structuredClone(findVisual(page, 0)),
    donut: structuredClone(findVisual(page, 13000)),
    table: structuredClone(findVisual(page, 32000)),
  };
  clearPageToChrome(page, [5000, 20000, 23000]);
  updateTextbox(page, 5000, "Arc Jumpstart | Best Practices");
  updateTextbox(page, 20000, "Arc SQL Best Practices Assessment");

  const resultCard = structuredClone(templates.card);
  setPosition(resultCard, {
    x: 16,
    y: 60,
    z: 60000,
    width: 600,
    height: 104,
    tabOrder: 60000,
  });
  stampVisualName(resultCard, page, 60000);
  replaceVisual(resultCard, {
    kpi_azure_sql_instance_count: "kpi_bpa_fail_count",
    "all_measures.kpi_azure_sql_instance_count":
      "all_measures.kpi_bpa_fail_count",
    kpi_azure_sql_cores: "kpi_bpa_warning_count",
    "all_measures.kpi_azure_sql_cores":
      "all_measures.kpi_bpa_warning_count",
    kpi_azure_sql_memory: "kpi_bpa_not_assessed_count",
    "all_measures.kpi_azure_sql_memory":
      "all_measures.kpi_bpa_not_assessed_count",
  });
  page.visualContainers.push(resultCard);
  setMeasureMetadata(
    page,
    60000,
    ["Failed checks", "Warnings", "Not assessed"],
    ["#,##0", "#,##0", "#,##0"],
  );
  compactKpiCard(page, 60000, "all_measures.kpi_bpa_fail_count");

  const coverageCard = structuredClone(templates.card);
  setPosition(coverageCard, {
    x: 630,
    y: 60,
    z: 61000,
    width: 606,
    height: 104,
    tabOrder: 61000,
  });
  stampVisualName(coverageCard, page, 61000);
  replaceVisual(coverageCard, {
    kpi_azure_sql_instance_count: "kpi_bpa_affected_machine_count",
    "all_measures.kpi_azure_sql_instance_count":
      "all_measures.kpi_bpa_affected_machine_count",
    kpi_azure_sql_cores: "kpi_bpa_check_count",
    "all_measures.kpi_azure_sql_cores":
      "all_measures.kpi_bpa_check_count",
    kpi_azure_sql_memory: "kpi_arc_instance_count",
    "all_measures.kpi_azure_sql_memory":
      "all_measures.kpi_arc_instance_count",
  });
  page.visualContainers.push(coverageCard);
  setMeasureMetadata(
    page,
    61000,
    ["Affected machines", "Checks represented", "Arc SQL instances"],
    ["#,##0", "#,##0", "#,##0"],
  );
  compactKpiCard(
    page,
    61000,
    "all_measures.kpi_bpa_affected_machine_count",
  );

  addPanel(
    page,
    templates,
    62000,
    { x: 16, y: 174, z: 62000, width: 390, height: 214 },
    "Results by status",
  );
  const statusChart = structuredClone(templates.donut);
  setPosition(statusChart, {
    x: 28,
    y: 206,
    z: 62002,
    width: 366,
    height: 170,
    tabOrder: 62002,
  });
  stampVisualName(statusChart, page, 62002);
  bindCategoryMeasure(
    statusChart,
    "view_best_practice_findings",
    "status",
    "Status",
    "kpi_bpa_finding_count",
    "Findings",
  );
  showDonutMetrics(statusChart);
  page.visualContainers.push(statusChart);

  addPanel(
    page,
    templates,
    63000,
    { x: 420, y: 174, z: 63000, width: 390, height: 214 },
    "Findings by category",
  );
  const categoryChart = structuredClone(templates.bar);
  setPosition(categoryChart, {
    x: 432,
    y: 206,
    z: 63002,
    width: 366,
    height: 170,
    tabOrder: 63002,
  });
  stampVisualName(categoryChart, page, 63002);
  bindCategoryMeasure(
    categoryChart,
    "view_best_practice_findings",
    "category",
    "Category",
    "kpi_bpa_finding_count",
    "Findings",
  );
  showBarMetrics(categoryChart);
  page.visualContainers.push(categoryChart);

  addPanel(
    page,
    templates,
    64000,
    { x: 824, y: 174, z: 64000, width: 412, height: 214 },
    "Findings by severity",
  );
  const severityChart = structuredClone(templates.donut);
  setPosition(severityChart, {
    x: 836,
    y: 206,
    z: 64002,
    width: 388,
    height: 170,
    tabOrder: 64002,
  });
  stampVisualName(severityChart, page, 64002);
  bindCategoryMeasure(
    severityChart,
    "view_best_practice_findings",
    "severity",
    "Severity",
    "kpi_bpa_finding_count",
    "Findings",
  );
  showDonutMetrics(severityChart);
  page.visualContainers.push(severityChart);

  addPanel(
    page,
    templates,
    65000,
    { x: 16, y: 400, z: 65000, width: 1220, height: 344 },
    "Best-practice findings, affected assets, and remediation",
  );
  const findingsTable = structuredClone(templates.table);
  setPosition(findingsTable, {
    x: 28,
    y: 432,
    z: 65002,
    width: 1196,
    height: 300,
    tabOrder: 65002,
  });
  stampVisualName(findingsTable, page, 65002);
  bindTable(findingsTable, "view_best_practice_findings", [
    { column: "check_id", label: "Check ID" },
    { column: "check_name", label: "Check" },
    { column: "category", label: "Category" },
    { column: "status", label: "Status" },
    { column: "severity", label: "Severity" },
    { column: "machine_name", label: "Machine" },
    { column: "sql_instance_name", label: "Instance" },
    { column: "sql_database_name", label: "Database" },
    { column: "current_value", label: "Current value" },
    { column: "expected_value", label: "Expected value" },
    { column: "remediation", label: "Remediation" },
    { column: "evidence_source", label: "Evidence source" },
  ]);
  page.visualContainers.push(findingsTable);

  return finalizePage(page, generatedPages[1], 6);
}

function buildDmvPage() {
  const page = structuredClone(sqlSource);
  const templates = {
    shape: structuredClone(findVisual(page, 1000)),
    title: structuredClone(findVisual(page, 5000)),
    body: structuredClone(findVisual(page, 7000)),
  };
  page.visualContainers = page.visualContainers.filter((visual) => {
    const config = getConfig(visual);
    const position = config.layouts?.[0]?.position ?? {};
    const visualType = config.singleVisual?.visualType;
    return (
      position.y < 65 ||
      visualType === "actionButton" ||
      getTabOrder(visual) === 23000
    );
  });
  updateTextbox(page, 5000, "Arc Jumpstart | DMV Audit");
  updateTextbox(page, 20000, "DMV Audit");

  function cloneTemplate(template, tabOrder, position) {
    const visual = structuredClone(template);
    setPosition(visual, { ...position, tabOrder });
    delete visual.query;
    delete visual.dataTransforms;
    const config = getConfig(visual);
    config.name = crypto
      .createHash("sha256")
      .update(`${generatedPages[2].name}:${config.name}:${tabOrder}`)
      .digest("hex")
      .slice(0, 20);
    visual.config = JSON.stringify(config);
    page.visualContainers.push(visual);
    return visual;
  }

  cloneTemplate(templates.shape, 50000, {
    x: 16,
    y: 82,
    z: 50000,
    width: 1220,
    height: 78,
  });
  const bannerTitle = cloneTemplate(templates.title, 51000, {
    x: 36,
    y: 92,
    z: 51000,
    width: 1160,
    height: 36,
  });
  setTextboxParagraphs(
    bannerTitle,
    ["DMV data source not configured - no audit findings are inferred"],
    "12pt",
  );
  const bannerBody = cloneTemplate(templates.body, 52000, {
    x: 36,
    y: 126,
    z: 52000,
    width: 1160,
    height: 36,
  });
  setTextboxParagraphs(
    bannerBody,
    [
      "Azure Resource Graph cannot return SQL DMV evidence. This page becomes data-bound after the approved read-only collector writes assessment results to the customer-owned evidence store.",
    ],
    "9pt",
  );

  const panels = [
    {
      x: 16,
      width: 385,
      title: "Collection and storage",
      body: [
        "1. Run approved read-only DMV scripts through Azure Arc Run Command.",
        "2. Stamp each result with assessment_run_id, collected_at, tenant, subscription, machine, instance, and database keys.",
        "3. Preferred store: Fabric Lakehouse Delta tables with Direct Lake.",
        "4. Lightweight alternative: ADLS Gen2 partitioned Parquet with Power BI incremental refresh.",
      ],
    },
    {
      x: 415,
      width: 400,
      title: "Audit domains",
      body: [
        "Edition downgrade blockers and Enterprise-only feature usage.",
        "Database compatibility, deprecated features, and configuration risks.",
        "CPU, memory, TempDB, storage latency, and workload pressure.",
        "High availability, disaster recovery, backup, and security posture.",
        "Collection coverage and failed or inaccessible instances.",
      ],
    },
    {
      x: 829,
      width: 407,
      title: "Planned DMV visuals",
      body: [
        "Audit coverage and collection freshness.",
        "Findings by severity, instance, database, and assessment run.",
        "Enterprise feature blockers and downgrade candidates.",
        "Capacity and performance hotspots with historical trends.",
        "Evidence detail with script version, source DMV, and remediation guidance.",
      ],
    },
  ];

  panels.forEach((panel, index) => {
    cloneTemplate(templates.shape, 60000 + index * 1000, {
      x: panel.x,
      y: 178,
      z: 60000 + index * 1000,
      width: panel.width,
      height: 510,
    });
    const title = cloneTemplate(templates.title, 60100 + index * 1000, {
      x: panel.x + 18,
      y: 194,
      z: 60100 + index * 1000,
      width: panel.width - 36,
      height: 48,
    });
    setTextboxParagraphs(title, [panel.title], "14pt");
    const body = cloneTemplate(templates.body, 60200 + index * 1000, {
      x: panel.x + 18,
      y: 248,
      z: 60200 + index * 1000,
      width: panel.width - 36,
      height: 400,
    });
    setTextboxParagraphs(body, [panel.body.join("\n\n")], "9pt");
  });

  return finalizePage(page, generatedPages[2], 7);
}

layout.sections = layout.sections.filter(
  (section) =>
    !generatedPages.some(
      (page) =>
        section.name === page.name || section.displayName === page.displayName,
    ) && section.displayName !== "Arc SQL Strategy",
);
layout.sections.push(
  buildSecurityPage(),
  buildBestPracticesPage(),
  buildDmvPage(),
);
fs.writeFileSync(outputPath, JSON.stringify(layout), "utf16le");
