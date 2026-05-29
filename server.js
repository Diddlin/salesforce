const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const port = Number(process.env.PORT) || 3000;
const indexPath = path.join(__dirname, 'index.html');
const DEFAULT_FIELD_PATH =
  process.env.WEB_AGENT_CUSTOMER_WEBSITE_FIELD ||
  'nolan_baily.customerWebsite';
const FALLBACK_FIELD_PATHS = [
  DEFAULT_FIELD_PATH,
  'nolan_baily.externalKnowledgeUrl',
  'nolan_baily.externalWebSdrUrl',
  'customer.externalKnowledgeUrl',
  'customer.externalWebSdrUrl',
  'External_Knowledge_URL__c',
  'External_Web_SDR_URL__c',
  'externalKnowledgeUrl',
  'externalWebSdrUrl'
];

const tenantCache = new Map();
const STOP_WORDS = new Set([
  'the',
  'and',
  'for',
  'with',
  'your',
  'that',
  'this',
  'from',
  'have',
  'are',
  'you',
  'our',
  'about',
  'into',
  'not',
  'all',
  'new',
  'can',
  'get',
  'use',
  'more',
  'how'
]);

function sendJson(res, status, payload) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 1_000_000) {
        reject(new Error('Request body too large'));
      }
    });
    req.on('end', () => {
      if (!data.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(data));
      } catch (e) {
        reject(new Error('Invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

function safeSlug(value) {
  return String(value || 'customer-demo')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
}

function getNestedValue(input, fieldPath) {
  return fieldPath
    .split('.')
    .filter(Boolean)
    .reduce((acc, key) => (acc && acc[key] != null ? acc[key] : undefined), input);
}

function normalizeWebsite(input) {
  if (!input || typeof input !== 'string') return null;
  const raw = input.trim();
  if (!raw) return null;
  try {
    return new URL(raw).toString();
  } catch (e) {
    try {
      return new URL(`https://${raw}`).toString();
    } catch (err) {
      return null;
    }
  }
}

function pickCustomerUrl(body) {
  if (body.url) return normalizeWebsite(body.url);
  const context = body.webAgentContext || body.customer || body;
  const explicitPaths = body.fieldPath
    ? String(body.fieldPath)
        .split(',')
        .map((p) => p.trim())
        .filter(Boolean)
    : [];

  const pathsToTry = [...explicitPaths, ...FALLBACK_FIELD_PATHS];
  for (const path of pathsToTry) {
    const value = getNestedValue(context, path);
    const normalized = normalizeWebsite(value);
    if (normalized) return normalized;
  }

  // Also check top-level keys in case payload comes flat from the web agent framework.
  const flatCandidates = [
    context.External_Knowledge_URL__c,
    context.External_Web_SDR_URL__c,
    context.externalKnowledgeUrl,
    context.externalWebSdrUrl
  ];
  for (const candidate of flatCandidates) {
    const normalized = normalizeWebsite(candidate);
    if (normalized) return normalized;
  }

  return null;
}

function htmlDecode(input) {
  return String(input || '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function extractTagText(html, regex) {
  const match = html.match(regex);
  return match ? htmlDecode(match[1].trim()) : '';
}

function extractMeta(html, name) {
  const re = new RegExp(
    `<meta[^>]+(?:name|property)=["']${name}["'][^>]+content=["']([^"']+)["'][^>]*>`,
    'i'
  );
  return extractTagText(html, re);
}

function stripHtmlText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractColors(html) {
  const colors = [];
  const regex = /#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b/g;
  const matches = html.match(regex) || [];
  for (const color of matches) {
    const normalized = color.length === 4
      ? `#${color[1]}${color[1]}${color[2]}${color[2]}${color[3]}${color[3]}`
      : color.toLowerCase();
    if (!colors.includes(normalized)) colors.push(normalized);
    if (colors.length >= 6) break;
  }
  return colors;
}

function extractTopTerms(text, maxTerms = 8) {
  const counts = new Map();
  const words = text.toLowerCase().match(/[a-z][a-z0-9-]{2,}/g) || [];
  for (const word of words) {
    if (STOP_WORDS.has(word)) continue;
    counts.set(word, (counts.get(word) || 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, maxTerms)
    .map(([term]) => term);
}

function pickIndustry(terms) {
  const joined = terms.join(' ');
  if (/health|patient|clinic|medical|care/.test(joined)) return 'Healthcare';
  if (/bank|finance|investment|insurance|payment/.test(joined)) return 'Financial Services';
  if (/retail|commerce|shop|cart|store/.test(joined)) return 'Retail';
  if (/factory|manufacturing|supply|industrial/.test(joined)) return 'Manufacturing';
  if (/software|platform|cloud|developer|api/.test(joined)) return 'Technology';
  if (/travel|tour|trip|booking|resort|hotel/.test(joined)) return 'Travel & Hospitality';
  return 'General Business';
}

function createKpiSet(industry) {
  const defaultKpis = [
    { label: 'Customer Sessions', value: '128', trend: '+12%' },
    { label: 'Support Deflection', value: '34%', trend: '+6%' },
    { label: 'Avg Response Time', value: '1.9s', trend: '-0.3s' }
  ];
  const byIndustry = {
    Technology: [
      { label: 'Product Trials', value: '84', trend: '+18%' },
      { label: 'API Success Rate', value: '99.2%', trend: '+0.4%' },
      { label: 'SE Demo Wins', value: '67%', trend: '+9%' }
    ],
    'Travel & Hospitality': [
      { label: 'Trip Requests', value: '146', trend: '+16%' },
      { label: 'Booking Conversion', value: '41%', trend: '+7%' },
      { label: 'Support SLA', value: '96%', trend: '+2%' }
    ],
    Retail: [
      { label: 'Cart Recovery', value: '22%', trend: '+4%' },
      { label: 'AOV Lift', value: '$48', trend: '+11%' },
      { label: 'Repeat Buyers', value: '39%', trend: '+5%' }
    ]
  };
  return byIndustry[industry] || defaultKpis;
}

function buildPackages(companyName, terms) {
  const safeTerms = terms.slice(0, 6);
  return [
    {
      name: `${companyName} Fast Start`,
      focus: 'Get a branded headless pilot live quickly.',
      highlights: [safeTerms[0], safeTerms[1], 'guided onboarding'].filter(Boolean)
    },
    {
      name: `${companyName} Support Assist`,
      focus: 'Ground WINT TMT Agentforce responses with customer context.',
      highlights: [safeTerms[2], safeTerms[3], 'case deflection'].filter(Boolean)
    },
    {
      name: `${companyName} Expansion`,
      focus: 'Scale to partner and service workflows across channels.',
      highlights: [safeTerms[4], safeTerms[5], 'cross-team rollout'].filter(Boolean)
    }
  ];
}

async function fetchHtml(url, timeoutMs = 7000) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      headers: {
        'User-Agent':
          'Salesforce-Headless-Demo-Builder/1.0 (+https://herokuapp.com)'
      },
      signal: controller.signal,
      redirect: 'follow'
    });
    if (!response.ok) {
      throw new Error(`Failed to fetch ${url}: ${response.status}`);
    }
    const html = await response.text();
    return html.slice(0, 300_000);
  } finally {
    clearTimeout(timeoutId);
  }
}

function extractInternalLinks(html, baseUrl, maxLinks = 3) {
  const links = [];
  const regex = /<a[^>]+href=["']([^"']+)["']/gi;
  let match;
  while ((match = regex.exec(html)) && links.length < maxLinks) {
    try {
      const link = new URL(match[1], baseUrl);
      if (
        link.origin === new URL(baseUrl).origin &&
        !link.hash &&
        !/\.(pdf|jpg|jpeg|png|svg|zip)$/i.test(link.pathname)
      ) {
        const normalized = `${link.origin}${link.pathname}`;
        if (!links.includes(normalized)) links.push(normalized);
      }
    } catch (e) {
      // Skip malformed links.
    }
  }
  return links;
}

async function lightweightCrawl(seedUrl) {
  const pages = [];
  const visited = new Set();
  const queue = [seedUrl];
  while (queue.length > 0 && pages.length < 3) {
    const current = queue.shift();
    if (!current || visited.has(current)) continue;
    visited.add(current);
    try {
      const html = await fetchHtml(current);
      const title = extractTagText(html, /<title[^>]*>([^<]*)<\/title>/i);
      const description = extractMeta(html, 'description');
      const text = stripHtmlText(html);
      const colors = extractColors(html);
      pages.push({
        url: current,
        title,
        description,
        textSample: text.slice(0, 1200),
        colors
      });
      const links = extractInternalLinks(html, current);
      for (const link of links) {
        if (!visited.has(link) && queue.length < 5) queue.push(link);
      }
    } catch (error) {
      pages.push({
        url: current,
        title: '',
        description: '',
        textSample: '',
        colors: [],
        error: error.message
      });
    }
  }
  return pages;
}

function buildTenantConfig(seedUrl, pages) {
  const firstPage = pages[0] || {};
  const origin = new URL(seedUrl);
  const companyName = (firstPage.title || origin.hostname.replace('www.', ''))
    .split(/[\-|:|•|\|]/)[0]
    .trim();
  const allText = pages.map((p) => p.textSample || '').join(' ');
  const allColors = [...new Set(pages.flatMap((p) => p.colors || []))];
  const terms = extractTopTerms(allText);
  const industry = pickIndustry(terms);
  const primary = allColors[0] || '#0b5cab';
  const accent = allColors[1] || '#06b6d4';
  const surface = '#0f172a';
  const kpis = createKpiSet(industry);
  const packages = buildPackages(companyName || 'Customer', terms);
  const challengeSummary =
    firstPage.description ||
    `Create a tailored ${industry.toLowerCase()} experience using web-grounded context and embedded support.`;

  return {
    tenantId: safeSlug(companyName || origin.hostname),
    companyName: companyName || 'Customer',
    website: seedUrl,
    sourcePages: pages.map((p) => p.url),
    summary: `Tailored demo for ${companyName || origin.hostname} based on lightweight crawl of ${pages.length} page(s).`,
    industry,
    challengeSummary,
    theme: {
      primary,
      accent,
      surface,
      text: '#e2e8f0'
    },
    grounding: {
      topTerms: terms,
      crawlMode: 'light',
      crawlPages: pages.length,
      snippets: pages
        .map((p) => ({
          url: p.url,
          title: p.title,
          description: p.description,
          warning: p.error || null
        }))
        .slice(0, 3)
    },
    kpis,
    packages,
    agentforce: {
      orgAlias: 'wint-tmt',
      mode: 'embedded-support',
      starterPrompts: [
        `Summarize ${companyName || 'this customer'} priorities from grounding context.`,
        `How can I position Agentforce support for ${industry} use cases?`,
        'What are the top next-best actions for a solution engineer demo?'
      ],
      notes:
        'Use these crawl snippets as low-cost grounding context before invoking the WINT TMT support agent.'
    },
    logoUrl: `${origin.origin}/favicon.ico`
  };
}

async function handleReskin(req, res) {
  try {
    const body = await readBody(req);
    const customerUrl = pickCustomerUrl(body);
    if (!customerUrl) {
      sendJson(res, 400, {
        error:
          'Provide a valid "url" or a webAgentContext value for the configured customer website field.'
      });
      return;
    }

    const pages = await lightweightCrawl(customerUrl);
    const config = buildTenantConfig(customerUrl, pages);
    tenantCache.set(config.tenantId, config);
    sendJson(res, 200, config);
  } catch (error) {
    sendJson(res, 500, { error: error.message });
  }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/health') {
    sendJson(res, 200, { ok: true, tenantCount: tenantCache.size });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/api/reskin') {
    handleReskin(req, res);
    return;
  }

  if (req.method === 'GET' && url.pathname.startsWith('/api/tenant/')) {
    const tenantId = url.pathname.replace('/api/tenant/', '');
    const config = tenantCache.get(tenantId);
    if (!config) {
      sendJson(res, 404, { error: 'Tenant not found' });
      return;
    }
    sendJson(res, 200, config);
    return;
  }

  fs.readFile(indexPath, 'utf8', (err, html) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Could not load index.html');
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  });
});

server.listen(port, () => {
  console.log(`Headless demo builder listening on port ${port}`);
  console.log(`Web Agent website field path: ${DEFAULT_FIELD_PATH}`);
});
