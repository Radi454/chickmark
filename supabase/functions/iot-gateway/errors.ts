// The device error contract, docs/IOT_API_CONTRACT.md section 11.
//
// This deliberately differs from the flat { error, code } used elsewhere in this
// repo: firmware needs `retryable` as a machine-readable field, and
// SCREAMING_SNAKE codes are visually distinct from the app-facing snake_case
// ones. The device contract is versioned independently of the app API.

import { nowSeconds } from './util.ts'

export type ErrorCode =
  | 'BAD_REQUEST'
  | 'DEVICE_UNAUTHORIZED'
  | 'DEVICE_REVOKED'
  | 'UNKNOWN_HUB'
  | 'UNKNOWN_SERIAL'
  | 'INVALID_FACTORY_SECRET'
  | 'INVALID_DEVICE_SECRET'
  | 'DEVICE_NOT_CLAIMED'
  | 'SECRET_ROTATION_REQUIRED'
  | 'PAYLOAD_TOO_LARGE'
  | 'UNPROCESSABLE'
  | 'RATE_LIMITED'
  | 'NOT_FOUND'
  | 'METHOD_NOT_ALLOWED'
  | 'SERVER_ERROR'

/** `retryable` means "resending this exact request unchanged may succeed". It is
 *  false for every code that requires a corrective action first (refresh the
 *  token, re-provision, shrink the batch) even though those flows do end in a
 *  retry. Firmware keys its decision table off this. */
const RETRYABLE: Record<ErrorCode, boolean> = {
  BAD_REQUEST: false,
  DEVICE_UNAUTHORIZED: false,
  DEVICE_REVOKED: false,
  UNKNOWN_HUB: false,
  UNKNOWN_SERIAL: false,
  INVALID_FACTORY_SECRET: false,
  INVALID_DEVICE_SECRET: false,
  DEVICE_NOT_CLAIMED: true,
  SECRET_ROTATION_REQUIRED: false,
  PAYLOAD_TOO_LARGE: false,
  UNPROCESSABLE: false,
  RATE_LIMITED: true,
  NOT_FOUND: false,
  METHOD_NOT_ALLOWED: false,
  SERVER_ERROR: true,
}

export const JSON_HEADERS = { 'Content-Type': 'application/json; charset=utf-8' }

export function ok(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify({ ...payload, server_time: nowSeconds() }), {
    status,
    headers: JSON_HEADERS,
  })
}

export function fail(
  status: number,
  code: ErrorCode,
  message: string,
  retryAfterSeconds: number | null = null,
): Response {
  const body = {
    error: {
      code,
      message,
      retryable: RETRYABLE[code] ?? status >= 500,
      retry_after_s: retryAfterSeconds,
    },
    server_time: nowSeconds(),
  }
  const headers: Record<string, string> = { ...JSON_HEADERS }
  if (retryAfterSeconds !== null) headers['Retry-After'] = String(retryAfterSeconds)
  return new Response(JSON.stringify(body), { status, headers })
}

export function retryableFor(code: ErrorCode): boolean {
  return RETRYABLE[code]
}
