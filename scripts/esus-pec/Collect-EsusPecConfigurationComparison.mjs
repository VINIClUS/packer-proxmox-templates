import fs from "node:fs";
import path from "node:path";
import { chromium } from "playwright";

const ROOT = process.cwd();
const OUTPUT_DIR = path.join(ROOT, "output", "esus-pec-config-comparison");
const OUTPUT_FILE = path.join(OUTPUT_DIR, "comparison-raw.json");

function loadDotEnv(filePath) {
  if (!fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const match = line.match(/^([A-Za-z0-9_]+)=(.*)$/);
    if (!match) continue;
    const [, key, rawValue] = match;
    if (!process.env[key]) {
      process.env[key] = rawValue.replace(/^"(.*)"$/, "$1").trim();
    }
  }
}

async function getInfisicalSecrets(secretPath) {
  const token = process.env.infisical_secret_key || process.env.INFISICAL_TOKEN;
  if (!token) throw new Error("Infisical token not found.");

  const baseUrl = process.env.INFISICAL_URL || "http://192.168.1.226:8080";
  const workspaceId = process.env.INFISICAL_WORKSPACE_ID || "2c83cfe9-e794-4961-977d-23000ae14461";
  const environment = process.env.INFISICAL_ENVIRONMENT || "dev";
  const url = new URL("/api/v3/secrets/raw", baseUrl);
  url.searchParams.set("workspaceId", workspaceId);
  url.searchParams.set("environment", environment);
  url.searchParams.set("secretPath", secretPath);

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (response.status === 404) return {};
  if (!response.ok) {
    throw new Error(`Infisical ${secretPath} returned HTTP ${response.status}`);
  }
  const body = await response.json();
  return Object.fromEntries((body.secrets || []).map((secret) => [secret.secretKey, secret.secretValue]));
}

const INSTALLATION_SECRET_PATHS = [
  "/test/InstallationConfig",
  "/test/InstallationConfig/FirstRun",
  "/test/InstallationConfig/TLS",
  "/test/InstallationConfig/Connectivity",
  "/test/InstallationConfig/Security",
  "/test/InstallationConfig/Municipality",
  "/test/InstallationConfig/Files",
  "/test/InstallationConfig/Advanced",
  "/test/InstallationConfig/GovBrOAuth",
  "/test/InstallationConfig/Importacao/CNES",
  "/test/InstallationConfig/Importacao/BolsaFamilia",
  "/test/InstallationConfig/Transmissao",
  "/test/InstallationConfig/Transmissao/API",
];

async function getInstallationConfigSecrets() {
  const merged = {};
  for (const secretPath of INSTALLATION_SECRET_PATHS) {
    Object.assign(merged, await getInfisicalSecrets(secretPath));
  }
  return merged;
}

function redact(value) {
  if (value == null) return value;
  const text = String(value);
  if (!text) return text;
  if (text.length <= 3) return "[REDACTED]";
  return `[REDACTED:${text.length}]`;
}

function sanitizeGraphqlPayload(payload) {
  return JSON.parse(JSON.stringify(payload, (key, value) => {
    if (/senha|password|token|secret|chave|authorization/i.test(key)) return redact(value);
    return value;
  }));
}

async function fillFirstVisible(page, selectors, value) {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if (await locator.count()) {
      try {
        await locator.fill(value, { timeout: 3000 });
        return selector;
      } catch {
        // Try the next candidate.
      }
    }
  }
  throw new Error(`Could not fill any selector: ${selectors.join(", ")}`);
}

async function clickFirstVisible(page, selectors) {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if (await locator.count()) {
      try {
        await locator.click({ timeout: 5000 });
        return selector;
      } catch {
        // Try the next candidate.
      }
    }
  }
  throw new Error(`Could not click any selector: ${selectors.join(", ")}`);
}

async function login(page, baseUrl, username, password) {
  console.error(`[login] ${baseUrl}`);
  await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.getByText("Aceitar todos", { exact: true }).click({ timeout: 2000 }).catch(() => {});

  const hasPassword = await page.locator('input[type="password"], input[name="password"]').count();
  if (!hasPassword) return { alreadyAuthenticated: true };

  const userSelector = await fillFirstVisible(page, [
    'input[name="username"]',
    'input[name="login"]',
    'input[name="cpf"]',
    'input[type="text"]',
    'input:not([type])',
  ], username);
  const passwordSelector = await fillFirstVisible(page, ['input[type="password"]', 'input[name="password"]'], password);
  const submitSelector = await clickFirstVisible(page, [
    'input[type="submit"]',
    'button[type="submit"]',
    'button:has-text("Entrar")',
    'button:has-text("Acessar")',
  ]);
  await page.locator(passwordSelector).first().press("Enter", { timeout: 2000 }).catch(() => {});
  await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(1500);
  if ((await page.getByText("Você já está logado em outra sessão", { exact: false }).count()) > 0) {
    await page.getByText("Continuar", { exact: true }).click({ timeout: 5000 });
    await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
  }
  await page.waitForTimeout(3500);
  if ((await page.getByText("Escolha um acesso para continuar", { exact: false }).count()) > 0) {
    await page.getByText("Administrador da Instalação", { exact: true }).first().click({ timeout: 10000 });
    await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(3500);
  }
  return { userSelector, passwordSelector, submitSelector };
}

async function collectPage(page, baseUrl, route) {
  console.error(`[route] ${baseUrl} ${route}`);
  const graphql = [];
  const responseListener = async (response) => {
    if (!response.url().includes("/api/graphql")) return;
    try {
      const request = response.request();
      const requestBody = request.postDataJSON?.() || null;
      const responseBody = await response.json();
      graphql.push({
        status: response.status(),
        operationName: Array.isArray(requestBody) ? requestBody.map((item) => item?.operationName) : requestBody?.operationName,
        request: sanitizeGraphqlPayload(requestBody),
        response: sanitizeGraphqlPayload(responseBody),
      });
    } catch {
      graphql.push({ status: response.status(), parseError: true });
    }
  };

  page.on("response", responseListener);
  const target = new URL(route, baseUrl).toString();
  await page.goto(target, { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(4500);

  const snapshot = await page.evaluate(() => {
    const labelFor = new Map(Array.from(document.querySelectorAll("label[for]")).map((label) => [label.getAttribute("for"), label.innerText.trim()]));
    const fieldLabel = (element) => {
      const id = element.getAttribute("id");
      if (id && labelFor.has(id)) return labelFor.get(id);
      const label = element.closest("label");
      if (label) return label.innerText.trim();
      const parent = element.closest("div, section, form, fieldset, tr");
      if (parent) {
        return parent.innerText.replace(/\s+/g, " ").trim().slice(0, 180);
      }
      return "";
    };
    const fields = Array.from(document.querySelectorAll("input, textarea, select")).map((element) => ({
      tag: element.tagName.toLowerCase(),
      type: element.getAttribute("type") || "",
      name: element.getAttribute("name") || "",
      id: element.getAttribute("id") || "",
      label: fieldLabel(element),
      value: element.type === "password" ? "[REDACTED]" : element.value,
      checked: element.type === "checkbox" || element.type === "radio" ? element.checked : undefined,
      disabled: element.disabled,
      placeholder: element.getAttribute("placeholder") || "",
      options: element.tagName.toLowerCase() === "select"
        ? Array.from(element.options).map((option) => ({ text: option.text, value: option.value, selected: option.selected }))
        : undefined,
    }));
    const buttons = Array.from(document.querySelectorAll("button, [role=button], a")).map((element) => ({
      text: element.innerText.replace(/\s+/g, " ").trim().slice(0, 160),
      href: element.getAttribute("href") || "",
      disabled: element.disabled || element.getAttribute("aria-disabled") === "true",
    })).filter((item) => item.text || item.href);
    return {
      title: document.title,
      url: location.href,
      headings: Array.from(document.querySelectorAll("h1,h2,h3,h4")).map((h) => h.innerText.trim()).filter(Boolean),
      text: document.body.innerText.replace(/\s+/g, " ").trim().slice(0, 20000),
      fields,
      buttons,
    };
  });
  page.off("response", responseListener);
  return { route, target, snapshot, graphql };
}

async function collectEnvironment(browser, env) {
  const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 1200 } });
  const page = await context.newPage();
  const loginResult = await login(page, env.baseUrl, env.username, env.password);
  const pages = [];
  for (const route of env.routes) {
    try {
      pages.push(await collectPage(page, env.baseUrl, route));
    } catch (error) {
      pages.push({
        route,
        error: error.message,
      });
      console.error(`[route-error] ${env.name} ${route}: ${error.message}`);
    }
  }
  await context.close();
  return {
    name: env.name,
    baseUrl: env.baseUrl,
    loginResult,
    collectedAt: new Date().toISOString(),
    pages,
  };
}

loadDotEnv(path.join(ROOT, ".env"));
fs.mkdirSync(OUTPUT_DIR, { recursive: true });

const localRuntime = await getInfisicalSecrets("/test");
const localInstall = await getInstallationConfigSecrets();

const routes = [
  "/configuracoes/instalacao",
  "/configuracoes/instalacao/conexao",
  "/configuracoes/instalacao/seguranca",
  "/configuracoes/instalacao/servidores",
  "/configuracoes/instalacao/municipios",
  "/configuracoes/instalacao/anexo",
  "/configuracoes/instalacao/avancadas",
  "/configuracoes/instalacao/unificacaobase",
  "/importarCnes",
  "/importar-bolsa-familia",
  "/configuracoes/transmissao",
  "/transmissao",
  "/transmissao/envio",
  "/transmissao/recebimento",
  "/transmissao/configuracoes",
];

const environments = [
  {
    name: "production",
    baseUrl: "https://esus.presidenteepitacio.sp.gov.br",
    username: process.env.user_esus_presidenteepitacio,
    password: process.env.password_esus_presidenteepitacio,
    routes,
  },
  {
    name: "local",
    baseUrl: localInstall.ESUS_PEC_LXC_TEST_HTTPS_URL || "https://192.168.1.209",
    username: process.env.user_esus_presidenteepitacio || localRuntime.ESUS_PEC_ADMIN_USERNAME || localInstall.ESUS_PEC_INSTALLER_CPF,
    password: process.env.password_esus_presidenteepitacio || localRuntime.ESUS_PEC_ADMIN_PASSWORD || localInstall.ESUS_PEC_INITIAL_PASSWORD,
    routes,
  },
];

for (const env of environments) {
  if (!env.username || !env.password) {
    throw new Error(`Missing credentials for ${env.name}`);
  }
}

const browser = await chromium.launch({ headless: true });
try {
  const result = {
    collectedAt: new Date().toISOString(),
    routes,
    environments: [],
  };
  for (const env of environments) {
    result.environments.push(await collectEnvironment(browser, env));
    fs.writeFileSync(OUTPUT_FILE, JSON.stringify(result, null, 2));
  }
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(result, null, 2));
  console.log(JSON.stringify({
    output: OUTPUT_FILE,
    environments: result.environments.map((env) => ({
      name: env.name,
      pages: env.pages.length,
      graphqlResponses: env.pages.reduce((sum, page) => sum + page.graphql.length, 0),
    })),
  }, null, 2));
} finally {
  await browser.close();
}
