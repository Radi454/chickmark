// supabase/functions/pip-realtime-session/fingerprint.ts
//
// The authorization fingerprint is a compact, deterministic digest of exactly
// what a live Realtime session is allowed to see. It is stamped on the session
// and on every generation at provisioning time and RE-DERIVED on every later
// authenticated call: if the recomputed value differs, the caller's authority
// changed while the session was open and the session must not be extended.
//
// Inputs, and only these:
//   * scope.staffLinkId       — identity anchor
//   * scope.accessRole        — 'admin' | 'customer'
//   * scope.allowedCustomerIds — the resolved allow-list
//   * profile.role            — so an admin -> customer demotion invalidates
//   * profile.status          — so an approved -> revoked flip invalidates
//
// Deliberately NOT included: conversationId, contextEpoch, stateVersion. Those
// churn on every turn, and a fingerprint that changes per turn would flag a
// normal conversation as an authority change on its second sentence.

export interface AuthorizationFingerprintInput {
  readonly staffLinkId: string
  readonly accessRole: string
  readonly allowedCustomerIds: readonly string[]
  readonly profileRole: string
  readonly profileStatus: string
}

/**
 * SHA-256 over a canonical, order-fixed encoding of the inputs. Customer ids are
 * sorted here as well as upstream so the digest cannot depend on the order a
 * caller happened to pass them in.
 */
export async function computeAuthorizationFingerprint(
  input: AuthorizationFingerprintInput,
): Promise<string> {
  const canonical = JSON.stringify({
    v: 1,
    staffLinkId: input.staffLinkId,
    accessRole: input.accessRole,
    allowedCustomerIds: [...input.allowedCustomerIds].sort(),
    profileRole: input.profileRole,
    profileStatus: input.profileStatus,
  })
  return await sha256Hex(canonical)
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}
