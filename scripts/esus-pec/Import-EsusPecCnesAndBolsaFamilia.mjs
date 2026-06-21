import fs from "node:fs";
import path from "node:path";
import { chromium } from "playwright";

const ROOT = process.cwd();

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

function parseArgs(argv) {
  const args = {
    cnesFile: "XmlParaESUS31_354130.zip",
    bolsaFile: "pbf_354130_12026_0.zip",
    timeoutMs: 20 * 60 * 1000,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      args[key] = next;
      i += 1;
    } else {
      args[key] = true;
    }
  }
  return args;
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

  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`Infisical ${secretPath} returned HTTP ${response.status}`);
  const body = await response.json();
  return Object.fromEntries((body.secrets || []).map((secret) => [secret.secretKey, secret.secretValue]));
}

async function setInfisicalSecret(secretPath, name, value, exists) {
  const token = process.env.infisical_secret_key || process.env.INFISICAL_TOKEN;
  const baseUrl = process.env.INFISICAL_URL || "http://192.168.1.226:8080";
  const workspaceId = process.env.INFISICAL_WORKSPACE_ID || "2c83cfe9-e794-4961-977d-23000ae14461";
  const projectSlug = process.env.INFISICAL_PROJECT_SLUG || "esus-pec-z-px-c";
  const environment = process.env.INFISICAL_ENVIRONMENT || "dev";
  const url = new URL(`/api/v3/secrets/raw/${encodeURIComponent(name)}`, baseUrl);
  const body = {
    environment,
    workspaceId,
    projectSlug,
    secretPath,
    secretValue: String(value ?? ""),
    skipMultilineEncoding: true,
    type: "shared",
    secretComment: "Managed by scripts/esus-pec/Import-EsusPecCnesAndBolsaFamilia.mjs",
  };

  const response = await fetch(url, {
    method: exists ? "PATCH" : "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    throw new Error(`Infisical upsert for ${name} returned HTTP ${response.status}`);
  }
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
  await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.getByText("Aceitar todos", { exact: true }).click({ timeout: 2000 }).catch(() => {});

  const hasPassword = await page.locator('input[type="password"], input[name="password"]').count();
  if (!hasPassword) return { alreadyAuthenticated: true };

  await fillFirstVisible(page, [
    'input[name="username"]',
    'input[name="login"]',
    'input[name="cpf"]',
    'input[type="text"]',
    'input:not([type])',
  ], username);
  await fillFirstVisible(page, ['input[type="password"]', 'input[name="password"]'], password);
  await clickFirstVisible(page, [
    'input[type="submit"]',
    'button[type="submit"]',
    'button:has-text("Entrar")',
    'button:has-text("Acessar")',
  ]);
  await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(1500);

  if ((await page.getByText(/j[aá] est[aá] logado/i).count()) > 0) {
    await page.getByText("Continuar", { exact: true }).click({ timeout: 5000 });
    await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
  }
  await page.waitForTimeout(3500);
  if ((await page.getByText(/Escolha um acesso para continuar/i).count()) > 0) {
    await page.getByText(/Administrador da Instala/i).first().click({ timeout: 10000 });
    await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(3500);
  }
  return { authenticated: true };
}

async function xsrfHeaders(context) {
  const cookies = await context.cookies();
  const xsrf = cookies.find((cookie) => cookie.name === "XSRF-TOKEN")?.value;
  return xsrf ? { "X-XSRF-TOKEN": decodeURIComponent(xsrf) } : {};
}

async function postGraphql(page, context, baseUrl, operations) {
  const response = await page.request.post(new URL("/api/graphql", baseUrl).toString(), {
    headers: await xsrfHeaders(context),
    data: operations,
    timeout: 60000,
  });
  const body = await response.json();
  if (!response.ok()) {
    throw new Error(`GraphQL returned HTTP ${response.status()}: ${JSON.stringify(body).slice(0, 500)}`);
  }
  return Array.isArray(body) ? body : [body];
}

async function getCnesImports(page, context, baseUrl, municipalityId) {
  const [result] = await postGraphql(page, context, baseUrl, [{
    operationName: "ImportacoesCnes",
    variables: {
      input: {
        municipioId: String(municipalityId),
        pageParams: { page: 0, size: 10, sort: ["-data"] },
      },
    },
    query: `query ImportacoesCnes($input: ImportacoesCnesQueryInput!) {
      importacoesCnes(input: $input) {
        content {
          id
          dataImportacao
          equipesNovas
          equipesAtualizadas
          lotacoesNovas
          lotacoesAtualizadas
          processo { id status }
          profissional { id nome nomeSocial }
          profissionaisNovos
          profissionaisAtualizados
          unidadesSaudeNovas
          unidadesSaudeAtualizadas
        }
        pageInfo { number size totalPages totalElements first last numberOfElements }
      }
    }`,
  }]);
  return result.data.importacoesCnes;
}

async function getBolsaImports(page, context, baseUrl) {
  const [result] = await postGraphql(page, context, baseUrl, [{
    operationName: "ImportacoesBolsaFamilia",
    variables: { input: { pageParams: { size: 10, sort: ["-dataImportacaoInicio"] } } },
    query: `query ImportacoesBolsaFamilia($input: ImportacaoBolsaFamiliaQueryInput!) {
      importacoesBolsaFamilia(input: $input) {
        content {
          id
          dataImportacaoInicio
          profissionalResponsavel { id nome }
          municipio { id nome }
          statusImportacao
          vigencia
          complementar
        }
        pageInfo { number size totalPages totalElements first last numberOfElements }
      }
    }`,
  }]);
  return result.data.importacoesBolsaFamilia;
}

async function uploadFile(page, context, baseUrl, endpoint, filePath) {
  const buffer = fs.readFileSync(filePath);
  const response = await page.request.post(new URL(endpoint, baseUrl).toString(), {
    headers: await xsrfHeaders(context),
    multipart: {
      file: {
        name: path.basename(filePath),
        mimeType: "application/zip",
        buffer,
      },
    },
    timeout: 120000,
  });
  const text = await response.text();
  if (!response.ok()) {
    throw new Error(`${endpoint} returned HTTP ${response.status()}: ${text.slice(0, 1000)}`);
  }
  return { status: response.status(), body: text.slice(0, 1000) };
}

async function pollUntil({ description, timeoutMs, intervalMs = 10000, read, isDone }) {
  const started = Date.now();
  let last;
  while (Date.now() - started < timeoutMs) {
    last = await read();
    if (isDone(last)) return last;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  throw new Error(`${description} did not reach a final state before timeout. Last state: ${JSON.stringify(last)}`);
}

async function upsertMetadata(secretPath, metadata) {
  const existing = await getInfisicalSecrets(secretPath);
  for (const [key, value] of Object.entries(metadata)) {
    await setInfisicalSecret(secretPath, key, value, Object.prototype.hasOwnProperty.call(existing, key));
  }
}

function newestItem(payload) {
  return payload?.content?.[0] || null;
}

loadDotEnv(path.join(ROOT, ".env"));
const args = parseArgs(process.argv.slice(2));
const runtimeSecrets = await getInfisicalSecrets("/test");
const installSecrets = await getInfisicalSecrets("/test/InstallationConfig");

const baseUrl = args.baseUrl || installSecrets.ESUS_PEC_LXC_TEST_HTTPS_URL || "https://192.168.1.209/";
const username = args.username || process.env.user_esus_presidenteepitacio || runtimeSecrets.ESUS_PEC_ADMIN_USERNAME || installSecrets.ESUS_PEC_INSTALLER_CPF;
const password = args.password || process.env.password_esus_presidenteepitacio || runtimeSecrets.ESUS_PEC_ADMIN_PASSWORD || installSecrets.ESUS_PEC_INITIAL_PASSWORD;
const municipalityId = args.municipalityId || installSecrets.ESUS_PEC_MUNICIPALITY_ID || "9946";

if (!username || !password) throw new Error("Missing PEC credentials.");
for (const requiredFile of [args.cnesFile, args.bolsaFile]) {
  if (!fs.existsSync(requiredFile)) throw new Error(`Missing import file: ${requiredFile}`);
}

const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 1200 } });
  const page = await context.newPage();
  await login(page, baseUrl, username, password);

  const results = { baseUrl, municipalityId, startedAt: new Date().toISOString() };

  if (!args.skipCnes) {
    const before = newestItem(await getCnesImports(page, context, baseUrl, municipalityId));
    results.cnesUpload = await uploadFile(page, context, baseUrl, `/api/cnes/${municipalityId}`, args.cnesFile);
    const cnes = await pollUntil({
      description: "CNES import",
      timeoutMs: Number(args.timeoutMs),
      read: async () => newestItem(await getCnesImports(page, context, baseUrl, municipalityId)),
      isDone: (item) => item && item.id !== before?.id && ["CONCLUIDO", "ERRO", "INTERROMPIDO"].includes(item.processo?.status),
    });
    results.cnes = cnes;
    if (cnes.processo?.status !== "CONCLUIDO") {
      throw new Error(`CNES import finished with status ${cnes.processo?.status}`);
    }
  }

  if (!args.skipBolsa) {
    const before = newestItem(await getBolsaImports(page, context, baseUrl));
    results.bolsaUpload = await uploadFile(page, context, baseUrl, "/api/bolsa-familia/importar", args.bolsaFile);
    const bolsa = await pollUntil({
      description: "Bolsa Familia import",
      timeoutMs: Number(args.timeoutMs),
      read: async () => newestItem(await getBolsaImports(page, context, baseUrl)),
      isDone: (item) => item && item.id !== before?.id && ["FINALIZADO", "FALHA"].includes(item.statusImportacao),
    });
    results.bolsaFamilia = bolsa;
    if (bolsa.statusImportacao !== "FINALIZADO") {
      throw new Error(`Bolsa Familia import finished with status ${bolsa.statusImportacao}`);
    }
  }

  results.completedAt = new Date().toISOString();
  await upsertMetadata("/test/InstallationConfig", {
    ESUS_PEC_CNES_IMPORT_LAST_RUN_AT: results.completedAt,
    ESUS_PEC_CNES_IMPORT_LAST_STATUS: results.cnes?.processo?.status || "",
    ESUS_PEC_CNES_IMPORT_LAST_IMPORT_ID: results.cnes?.id || "",
    ESUS_PEC_CNES_IMPORT_LAST_PROCESS_ID: results.cnes?.processo?.id || "",
    ESUS_PEC_CNES_IMPORT_LAST_MUNICIPALITY_ID: String(municipalityId),
    ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_RUN_AT: results.completedAt,
    ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_STATUS: results.bolsaFamilia?.statusImportacao || "",
    ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_IMPORT_ID: results.bolsaFamilia?.id || "",
    ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_VIGENCIA: results.bolsaFamilia?.vigencia || "",
  });

  console.log(JSON.stringify(results, null, 2));
} finally {
  await browser.close();
}
