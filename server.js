const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const port = Number(process.env.PORT) || 3000;
const indexPath = path.join(__dirname, 'tahoe.html');
const DEFAULT_FIELD_PATH =
  process.env.WEB_AGENT_CUSTOMER_WEBSITE_FIELD ||
  'nolan_baily.customerWebsite';
const AGENT_SUPPORT_ENDPOINT = process.env.AGENT_SUPPORT_ENDPOINT || '';
const AGENTFORCE_EMBED_URL = process.env.AGENTFORCE_EMBED_URL || '';
const EMBEDDED_MESSAGING_ORG_ID =
  process.env.EMBEDDED_MESSAGING_ORG_ID || '00DKj00000ibSAG';
const EMBEDDED_MESSAGING_DEPLOYMENT =
  process.env.EMBEDDED_MESSAGING_DEPLOYMENT || 'Tech_IDO_Web_SDR_Deployment';
const EMBEDDED_MESSAGING_SITE_URL =
  process.env.EMBEDDED_MESSAGING_SITE_URL ||
  'https://storm-971f7eb7643997.my.site.com/ESWTechIDOWebSDRDeplo1762196766193';
const EMBEDDED_MESSAGING_SCRT2_URL =
  process.env.EMBEDDED_MESSAGING_SCRT2_URL ||
  'https://storm-971f7eb7643997.my.salesforce-scrt.com';
const EMBEDDED_MESSAGING_BOOTSTRAP_URL =
  process.env.EMBEDDED_MESSAGING_BOOTSTRAP_URL ||
  'https://storm-971f7eb7643997.my.site.com/ESWTechIDOWebSDRDeplo1762196766193/assets/js/bootstrap.min.js';
const CRAWL_PROFILES = {
  light: { maxPages: 3, maxLinksPerPage: 3, maxCssFiles: 0, timeoutMs: 7000 },
  deep: { maxPages: 15, maxLinksPerPage: 12, maxCssFiles: 12, timeoutMs: 12000 }
};
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

function extractFirstMatch(html, regex) {
  const match = html.match(regex);
  return match ? htmlDecode(match[1].trim()) : '';
}

function extractNavItems(html, maxItems = 6) {
  const out = [];
  const regex = /<a[^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = regex.exec(html)) && out.length < maxItems) {
    const text = stripHtmlText(match[1] || '').trim();
    if (text.length >= 3 && text.length <= 28 && !out.includes(text)) {
      out.push(text);
    }
  }
  return out;
}

function extractButtonLabels(html, maxItems = 8) {
  const out = [];
  const regex = /<(button|a)[^>]*>([\s\S]*?)<\/(button|a)>/gi;
  let match;
  while ((match = regex.exec(html)) && out.length < maxItems) {
    const text = stripHtmlText(match[2] || '').trim();
    if (text.length >= 3 && text.length <= 40 && !out.includes(text)) {
      out.push(text);
    }
  }
  return out;
}

function extractHeadings(html, maxItems = 6) {
  const out = [];
  const regex = /<h[12][^>]*>([\s\S]*?)<\/h[12]>/gi;
  let match;
  while ((match = regex.exec(html)) && out.length < maxItems) {
    const text = stripHtmlText(match[1] || '').trim();
    if (text.length >= 6 && text.length <= 110 && !out.includes(text)) {
      out.push(text);
    }
  }
  return out;
}

function extractHeroHeading(html) {
  return (
    extractFirstMatch(html, /<h1[^>]*>([\s\S]*?)<\/h1>/i) ||
    extractMeta(html, 'og:title') ||
    extractTagText(html, /<title[^>]*>([^<]*)<\/title>/i)
  );
}

function extractThemeColor(html) {
  return (
    extractMeta(html, 'theme-color') ||
    extractMeta(html, 'msapplication-TileColor') ||
    ''
  );
}

function extractOgImage(html) {
  return extractMeta(html, 'og:image') || extractMeta(html, 'twitter:image') || '';
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

function hashString(input) {
  let h = 0;
  const s = String(input || '');
  for (let i = 0; i < s.length; i += 1) {
    h = (h << 5) - h + s.charCodeAt(i);
    h |= 0;
  }
  return Math.abs(h);
}

function seededHexColor(seed, offset = 0) {
  const n = (hashString(seed) + offset) % 0xffffff;
  const hex = n.toString(16).padStart(6, '0');
  return `#${hex}`;
}

const VISUAL_ARCHETYPES = {
  enterprise: { surface: '#0a1020', text: '#e2e8f0' },
  consumer: { surface: '#1a1027', text: '#f8fafc' },
  startup: { surface: '#071a16', text: '#ecfeff' }
};

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

async function fetchText(url, timeoutMs = 7000) {
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
    return (await response.text()).slice(0, 300_000);
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

function extractStylesheetLinks(html, baseUrl, maxLinks = 6) {
  const out = [];
  const regex = /<link[^>]+rel=["'][^"']*stylesheet[^"']*["'][^>]+href=["']([^"']+)["']/gi;
  let match;
  while ((match = regex.exec(html)) && out.length < maxLinks) {
    try {
      const link = new URL(match[1], baseUrl);
      if (!out.includes(link.toString())) out.push(link.toString());
    } catch (e) {
      // ignore
    }
  }
  return out;
}

function extractFontFamilies(cssText, maxFonts = 8) {
  const fonts = [];
  const regex = /font-family\s*:\s*([^;]+);/gi;
  let match;
  while ((match = regex.exec(cssText)) && fonts.length < maxFonts) {
    const first = match[1].split(',')[0].replace(/["']/g, '').trim();
    if (first && !fonts.includes(first)) fonts.push(first);
  }
  return fonts;
}

async function crawlSite(seedUrl, mode = 'light') {
  const profile = CRAWL_PROFILES[mode] || CRAWL_PROFILES.light;
  const pages = [];
  const visited = new Set();
  const queue = [seedUrl];
  if (mode === 'deep') {
    const origin = new URL(seedUrl).origin;
    const canonical = ['/about', '/products', '/solutions', '/pricing', '/support', '/contact', '/blog'];
    for (const p of canonical) {
      queue.push(`${origin}${p}`);
    }
  }
  while (queue.length > 0 && pages.length < profile.maxPages) {
    const current = queue.shift();
    if (!current || visited.has(current)) continue;
    visited.add(current);
    try {
      const html = await fetchHtml(current, profile.timeoutMs);
      const title = extractTagText(html, /<title[^>]*>([^<]*)<\/title>/i);
      const description = extractMeta(html, 'description');
      const text = stripHtmlText(html);
      const colors = extractColors(html);
      const cssLinks =
        mode === 'deep'
          ? extractStylesheetLinks(html, current, profile.maxCssFiles)
          : [];
      let cssColors = [];
      let cssFonts = [];
      if (mode === 'deep' && cssLinks.length) {
        for (const cssUrl of cssLinks) {
          try {
            const css = await fetchText(cssUrl, profile.timeoutMs);
            cssColors = [...cssColors, ...extractColors(css)];
            cssFonts = [...cssFonts, ...extractFontFamilies(css)];
          } catch (e) {
            // ignore css fetch failures
          }
        }
      }
      pages.push({
        url: current,
        title,
        description,
        textSample: text.slice(0, 1200),
        colors,
        cssColors: [...new Set(cssColors)].slice(0, 8),
        cssFonts: [...new Set(cssFonts)].slice(0, 8),
        rawHtml: html.slice(0, 80000)
      });
      const links = extractInternalLinks(html, current, profile.maxLinksPerPage);
      for (const link of links) {
        if (!visited.has(link) && queue.length < profile.maxPages * 2) queue.push(link);
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
  return { pages, mode };
}

function buildTenantConfig(seedUrl, crawlResult) {
  const pages = crawlResult.pages || [];
  const mode = crawlResult.mode || 'light';
  const firstPage = pages[0] || {};
  const origin = new URL(seedUrl);
  const firstHtml = firstPage.rawHtml || '';
  const companyName = (firstPage.title || origin.hostname.replace('www.', ''))
    .split(/[\-|:|•|\|]/)[0]
    .trim();
  const allText = pages.map((p) => p.textSample || '').join(' ');
  const allColors = [
    ...new Set(
      pages.flatMap((p) => [...(p.colors || []), ...(p.cssColors || [])])
    )
  ];
  const allFonts = [...new Set(pages.flatMap((p) => p.cssFonts || []))];
  const terms = extractTopTerms(allText);
  const industry = pickIndustry(terms);
  const themeColor = extractThemeColor(firstHtml);
  const seededPrimary = seededHexColor(origin.hostname, 131);
  const seededAccent = seededHexColor(origin.hostname, 9973);
  const primary = themeColor || allColors[0] || seededPrimary;
  const accent = allColors[1] || seededAccent;
  const surface = '#0f172a';
  const kpis = createKpiSet(industry);
  const packages = buildPackages(companyName || 'Customer', terms);
  const challengeSummary =
    firstPage.description ||
    `Create a tailored ${industry.toLowerCase()} experience using web-grounded context and embedded support.`;
  const heroTitle = extractHeroHeading(firstHtml) || `Welcome to ${companyName}`;
  const navItems = extractNavItems(firstHtml);
  const ctaLabels = extractButtonLabels(firstHtml);
  const headings = extractHeadings(firstHtml);
  const heroImage = extractOgImage(firstHtml);
  const logoUrl = heroImage || `${origin.origin}/favicon.ico`;
  const vibeTags = [
    ...terms.slice(0, 4),
    ...(headings[0] ? [headings[0].split(' ').slice(0, 3).join(' ')] : [])
  ].filter(Boolean);
  const signalStrength =
    (navItems.length ? 1 : 0) +
    (ctaLabels.length ? 1 : 0) +
    (headings.length ? 1 : 0) +
    (heroImage ? 1 : 0) +
    (allFonts.length ? 1 : 0) +
    (terms.length ? 1 : 0);
  const fidelity = signalStrength >= 5 ? 'high' : signalStrength >= 3 ? 'medium' : 'low';

  return {
    tenantId: safeSlug(companyName || origin.hostname),
    companyName: companyName || 'Customer',
    website: seedUrl,
    sourcePages: pages.map((p) => p.url),
    summary: `Tailored demo for ${companyName || origin.hostname} based on deep crawl of ${pages.length} page(s).`,
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
      crawlMode: mode,
      crawlPages: pages.length,
      signalStrength,
      fidelity,
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
    brand: {
      heroTitle,
      navItems: navItems.length ? navItems : ['Home', 'Solutions', 'Support', 'About'],
      heroImage,
      logoUrl,
      fonts: allFonts.slice(0, 4),
      headings,
      ctaLabels,
      vibeTags
    },
    agentforce: {
      orgAlias: 'wint-tmt',
      mode: 'embedded-support',
      embedUrl: AGENTFORCE_EMBED_URL,
      embeddedMessaging: {
        orgId: EMBEDDED_MESSAGING_ORG_ID,
        deploymentName: EMBEDDED_MESSAGING_DEPLOYMENT,
        siteUrl: EMBEDDED_MESSAGING_SITE_URL,
        scrt2Url: EMBEDDED_MESSAGING_SCRT2_URL,
        bootstrapUrl: EMBEDDED_MESSAGING_BOOTSTRAP_URL
      },
      starterPrompts: [
        `Act as a concierge and summarize ${companyName || 'this customer'} priorities from grounding context.`,
        `What concierge-style support journey should I run for ${industry} use cases?`,
        'What are the top next-best actions for a support-first demo?'
      ],
      notes:
        'Use these crawl snippets as grounding context for a concierge-style Agentforce support interaction.'
    },
    logoUrl
  };
}

function applyVisualArchetype(config, archetype) {
  const selected = VISUAL_ARCHETYPES[archetype];
  if (!selected) return config;
  return {
    ...config,
    theme: {
      ...config.theme,
      surface: selected.surface,
      text: selected.text
    },
    brand: {
      ...config.brand,
      archetype
    }
  };
}

function buildGroundingBrief(config) {
  const snippets = (config.grounding?.snippets || [])
    .map((s) => `${s.title || 'Untitled'}: ${s.description || ''} (${s.url})`)
    .join(' | ')
    .slice(0, 1200);
  return {
    companyName: config.companyName,
    industry: config.industry,
    topTerms: config.grounding?.topTerms || [],
    challengeSummary: config.challengeSummary || '',
    snippets
  };
}

function localSupportReply(config, message) {
  const lower = String(message || '').toLowerCase();
  const terms = config.grounding?.topTerms || [];
  const packs = config.packages || [];

  if (lower.includes('next step') || lower.includes('what should')) {
    return `Concierge recommendation for ${config.companyName}: start with "${packs[0]?.name || 'Fast Start'}", center the conversation on ${terms.slice(0, 2).join(', ') || 'customer priorities'}, and then transition into Agentforce-led support deflection using grounded snippets from their website.`;
  }
  if (lower.includes('agent') || lower.includes('support')) {
    return `Use the WINT TMT concierge flow: pre-seed context with ${terms.slice(0, 3).join(', ') || 'top customer themes'}, then handle Q&A, guidance, and case triage in embedded chat.`;
  }
  if (lower.includes('package') || lower.includes('pricing')) {
    return `Concierge package path: 1) ${packs[0]?.name || 'Fast Start'}, 2) ${packs[1]?.name || 'Support Assist'}, 3) ${packs[2]?.name || 'Expansion'}. This shows quick value, support maturity, and scalable expansion.`;
  }
  return `Based on ${config.companyName}'s site signals (${terms.slice(0, 4).join(', ') || 'general business context'}), I recommend a concierge-led experience with fast branding, grounded support, and a clear KPI-driven rollout path.`;
}

function extractSupportText(payload) {
  if (!payload) return '';
  if (typeof payload === 'string') return payload;
  return (
    payload.reply ||
    payload.response ||
    payload.message ||
    payload.outputText ||
    payload.text ||
    payload.answer ||
    ''
  );
}

async function handleReskin(req, res) {
  try {
    const body = await readBody(req);
    const customerUrl = pickCustomerUrl(body);
    const mode = 'deep';
    const archetype = String(body.archetype || 'auto');
    if (!customerUrl) {
      sendJson(res, 400, {
        error:
          'Provide a valid "url" or a webAgentContext value for the configured customer website field.'
      });
      return;
    }

    const crawlResult = await crawlSite(customerUrl, mode);
    let config = buildTenantConfig(customerUrl, crawlResult);
    if (archetype !== 'auto') {
      config = applyVisualArchetype(config, archetype);
    } else {
      const autoArchetype =
        config.industry === 'Financial Services' || config.industry === 'Healthcare'
          ? 'enterprise'
          : config.industry === 'Retail' || config.industry === 'Travel & Hospitality'
            ? 'consumer'
            : 'startup';
      config = applyVisualArchetype(config, autoArchetype);
    }
    tenantCache.set(config.tenantId, config);
    sendJson(res, 200, config);
  } catch (error) {
    sendJson(res, 500, { error: error.message });
  }
}

async function handleSupport(req, res) {
  try {
    const body = await readBody(req);
    const tenantId = body.tenantId;
    const message = String(body.message || '').trim();
    if (!tenantId || !message) {
      sendJson(res, 400, { error: 'tenantId and message are required.' });
      return;
    }

    const config = tenantCache.get(tenantId);
    if (!config) {
      sendJson(res, 404, { error: 'Tenant not found.' });
      return;
    }

    const groundingBrief = buildGroundingBrief(config);

    if (AGENT_SUPPORT_ENDPOINT) {
      try {
        const upstream = await fetch(AGENT_SUPPORT_ENDPOINT, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            tenantId,
            message,
            history: body.history || [],
            grounding: groundingBrief,
            orgAlias: config.agentforce?.orgAlias || 'wint-tmt'
          })
        });
        const data = await upstream.json().catch(() => ({}));
        if (upstream.ok) {
          const reply = extractSupportText(data);
          if (reply) {
            sendJson(res, 200, {
              mode: 'upstream-agent',
              reply
            });
            return;
          }
        }
      } catch (e) {
        // Fall through to local fallback response.
      }
    }

    const fallbackReply = localSupportReply(config, message);
    sendJson(res, 200, {
      mode: 'local-fallback',
      reply: fallbackReply
    });
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

  if (req.method === 'POST' && url.pathname === '/api/support') {
    handleSupport(req, res);
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
      res.end('Could not load tahoe.html');
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  });
});

server.listen(port, () => {
  console.log(`Headless demo builder listening on port ${port}`);
  console.log(`Web Agent website field path: ${DEFAULT_FIELD_PATH}`);
  console.log(
    `Support endpoint mode: ${AGENT_SUPPORT_ENDPOINT ? 'upstream' : 'local-fallback'}`
  );
  console.log(
    `Agentforce embed mode: ${AGENTFORCE_EMBED_URL ? 'iframe' : 'not-configured'}`
  );
  console.log(
    `Embedded messaging mode: ${EMBEDDED_MESSAGING_BOOTSTRAP_URL ? 'script-enabled' : 'not-configured'}`
  );
});
