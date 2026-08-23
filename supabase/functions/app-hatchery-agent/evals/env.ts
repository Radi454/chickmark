// OPENROUTER_API_KEY loading for the text-agent model-acceptance harness.
//
// Reads the environment first. If unset, falls back to parsing the repo's
// gitignored `.env` (see `.gitignore`: `.env`, `.env.local`, ...) at the repo
// root, so `deno run --allow-net --allow-env --allow-read` works the same way
// whether the key was exported in the shell or only placed in `.env`.
//
// The key is NEVER logged, NEVER written into any output file (including
// `--json`), and NEVER echoed back in any assertion detail. Every diagnostic
// string in this harness that could theoretically carry it (HTTP error
// bodies, etc.) is built from the RESPONSE, not the request, so the key
// itself never flows through this module's own log lines.

const ENV_VAR_NAME = 'OPENROUTER_API_KEY'

/** `evals/env.ts` -> `app-hatchery-agent` -> `functions` -> `supabase` -> repo root. */
const REPO_ROOT_ENV_FILE = new URL('../../../../.env', import.meta.url)

function parseDotEnv(text: string): Map<string, string> {
  const values = new Map<string, string>()
  for (const rawLine of text.split('\n')) {
    const line = rawLine.trim()
    if (line === '' || line.startsWith('#')) continue
    const eq = line.indexOf('=')
    if (eq <= 0) continue
    const key = line.slice(0, eq).trim()
    let value = line.slice(eq + 1).trim()
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1)
    }
    values.set(key, value)
  }
  return values
}

/**
 * Best-effort `.env` read. Missing file, unreadable file, or missing
 * `--allow-read` all resolve to `null` rather than throwing -- the caller's
 * job is to give a clear "not set" error either way, not to distinguish why
 * the fallback didn't help.
 */
async function readDotEnvValue(name: string): Promise<string | null> {
  try {
    const text = await Deno.readTextFile(REPO_ROOT_ENV_FILE)
    return parseDotEnv(text).get(name) ?? null
  } catch {
    return null
  }
}

/** Returns the trimmed key, or `null` if it is not set anywhere. Never logs it. */
export async function readOpenRouterApiKey(): Promise<string | null> {
  const fromEnv = Deno.env.get(ENV_VAR_NAME)
  if (fromEnv && fromEnv.trim().length > 0) return fromEnv.trim()
  const fromDotEnv = await readDotEnvValue(ENV_VAR_NAME)
  if (fromDotEnv && fromDotEnv.trim().length > 0) return fromDotEnv.trim()
  return null
}

/**
 * Same as `readOpenRouterApiKey`, but prints a clear error and exits the
 * process (code 1) instead of returning `null`. Use from a CLI `main()`.
 */
export async function requireOpenRouterApiKey(): Promise<string> {
  const key = await readOpenRouterApiKey()
  if (key) return key
  console.error(`${ENV_VAR_NAME} is not set.`)
  console.error('Set it in your shell, e.g.:')
  console.error(`  export ${ENV_VAR_NAME}="sk-or-..."`)
  console.error(
    `Or place it in the repo's gitignored .env at the repo root (KEY=VALUE, one per ` +
      `line) and re-run with --allow-read so this loader can find it:`,
  )
  console.error(`  ${ENV_VAR_NAME}=sk-or-...`)
  Deno.exit(1)
}
