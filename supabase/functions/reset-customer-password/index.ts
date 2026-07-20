import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (request.method !== 'POST') {
    return json(405, { error: 'Method not allowed.' })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = request.headers.get('Authorization')
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json(500, { error: 'Customer account service is not configured.' })
  }
  if (!authorization) {
    return json(401, { error: 'Sign in as an admin to reset passwords.' })
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  })
  const { data: authData, error: authError } = await callerClient.auth.getUser()
  if (authError || !authData.user) {
    return json(401, { error: 'Your admin session is not valid.' })
  }
  const { data: callerProfile, error: callerError } = await callerClient
    .from('profiles')
    .select('role, status')
    .eq('id', authData.user.id)
    .single()
  if (
    callerError ||
    callerProfile?.role !== 'admin' ||
    callerProfile?.status !== 'approved'
  ) {
    return json(403, { error: 'Only an approved admin can reset customer passwords.' })
  }

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch (_) {
    return json(400, { error: 'Invalid request body.' })
  }
  const userId = String(body.userId ?? '').trim()
  const password = String(body.password ?? '')
  if (!userId) return json(400, { error: 'Customer account is required.' })
  if (
    password.length < 12 ||
    !/[a-z]/.test(password) ||
    !/[A-Z]/.test(password) ||
    !/[0-9]/.test(password) ||
    !/[^A-Za-z0-9]/.test(password)
  ) {
    return json(400, {
      error: 'Password must be 12+ characters with uppercase, lowercase, number, and symbol.',
    })
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: target, error: targetError } = await adminClient
    .from('profiles')
    .select('id, role')
    .eq('id', userId)
    .maybeSingle()
  if (targetError || target?.role !== 'customer') {
    return json(400, { error: 'The selected identity is not a customer account.' })
  }

  const { error: updateError } = await adminClient.auth.admin.updateUserById(
    userId,
    { password },
  )
  if (updateError) {
    return json(400, { error: updateError.message })
  }
  return json(200, { success: true })
})
