#!/usr/bin/env node

import fs from "node:fs";

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.error("Missing Playwright dependency. Run: npm install --no-save playwright");
  process.exit(1);
}

function loadEnv(path) {
  const env = {};
  if (!fs.existsSync(path)) return env;
  for (const line of fs.readFileSync(path, "utf8").split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!match) continue;
    env[match[1]] = match[2].replace(/^['"]|['"]$/g, "");
  }
  return env;
}

function getArg(name, fallback) {
  const prefix = `--${name}=`;
  const arg = process.argv.find((item) => item.startsWith(prefix));
  return arg ? arg.slice(prefix.length) : fallback;
}

async function fillFirstVisible(page, selectors, value) {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if (await locator.isVisible({ timeout: 2500 }).catch(() => false)) {
      await locator.fill(value);
      return selector;
    }
  }
  throw new Error(`No visible input found for ${selectors.join(", ")}`);
}

async function clickFirstVisible(page, selectors) {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if (await locator.isVisible({ timeout: 2500 }).catch(() => false)) {
      await locator.click();
      return selector;
    }
  }
  throw new Error(`No visible button found for ${selectors.join(", ")}`);
}

async function loginAsInstallationAdmin(page, username, password, baseUrl) {
  await page.goto(baseUrl, { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.getByText("Aceitar todos", { exact: true }).click({ timeout: 2000 }).catch(() => {});

  const passwordInputs = await page.locator('input[type="password"], input[name="password"]').count();
  if (passwordInputs === 0) return { alreadyAuthenticated: true, finalUrl: page.url() };

  const userSelector = await fillFirstVisible(page, [
    'input[name="username"]',
    'input[name="login"]',
    'input[name="cpf"]',
    'input[type="text"]',
    "input:not([type])",
  ], username);
  const passwordSelector = await fillFirstVisible(page, [
    'input[type="password"]',
    'input[name="password"]',
  ], password);
  const submitSelector = await clickFirstVisible(page, [
    'input[type="submit"]',
    'button[type="submit"]',
    'button:has-text("Entrar")',
    'button:has-text("Acessar")',
  ]);

  await page.locator(passwordSelector).first().press("Enter", { timeout: 2000 }).catch(() => {});
  await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(2000);

  if ((await page.getByText(/j[aáÃ] est[aáÃ] logado/i).count()) > 0) {
    await page.getByText("Continuar", { exact: true }).click({ timeout: 5000 });
    await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
  }

  await page.waitForTimeout(3500);
  if ((await page.getByText(/Escolha um acesso para continuar/i).count()) > 0) {
    await page.getByText(/Administrador da Instala/i).first().click({ timeout: 10000 });
    await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(3500);
  }

  return { userSelector, passwordSelector, submitSelector, finalUrl: page.url() };
}

async function main() {
  const env = { ...process.env, ...loadEnv(".env") };
  const username = env.user_esus_presidenteepitacio;
  const password = env.password_esus_presidenteepitacio;
  if (!username || !password) {
    throw new Error("Missing user_esus_presidenteepitacio or password_esus_presidenteepitacio in environment or .env");
  }

  const baseUrl = getArg("base-url", "https://esus.presidenteepitacio.sp.gov.br/");
  const hostResolverIp = getArg("host-resolver-ip", "192.168.1.209");
  const domain = new URL(baseUrl).hostname;
  const browser = await chromium.launch({
    headless: true,
    args: [`--host-resolver-rules=MAP ${domain} ${hostResolverIp}`],
  });

  try {
    const context = await browser.newContext({ ignoreHTTPSErrors: true });
    const page = await context.newPage();
    const loginState = await loginAsInstallationAdmin(page, username, password, baseUrl);
    const cookies = await context.cookies();
    const xsrf = cookies.find((cookie) => cookie.name === "XSRF-TOKEN")?.value;
    const response = await page.request.post(new URL("/api/graphql", baseUrl).toString(), {
      headers: xsrf ? {
        "X-XSRF-TOKEN": decodeURIComponent(xsrf),
        Origin: new URL(baseUrl).origin,
        Referer: page.url(),
      } : {},
      data: [{
        operationName: "Configuracoes",
        variables: {},
        query: "query Configuracoes { info { govBREnabled } }",
      }],
      timeout: 60000,
    });

    const text = await response.text();
    const body = JSON.parse(text);
    const govbrEnabled = body?.[0]?.data?.info?.govBREnabled;
    const result = {
      baseUrl,
      hostResolverIp,
      finalUrl: loginState.finalUrl,
      httpStatus: response.status(),
      contentType: response.headers()["content-type"] || "",
      govBREnabled: govbrEnabled,
      validation: response.ok() && govbrEnabled === true ? "passed" : "failed",
    };
    console.log(JSON.stringify(result, null, 2));
    if (result.validation !== "passed") process.exit(2);
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
