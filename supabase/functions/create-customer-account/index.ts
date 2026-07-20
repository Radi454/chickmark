import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const customerEmailDomain = 'customers.chickmark.app'
const usernamePattern = /^[a-z0-9][a-z0-9._-]{2,39}$/

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
    return json(401, { error: 'Sign in as an admin to create accounts.' })
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  })
  const { data: authData, error: authError } = await callerClient.auth.getUser()
  if (authError || !authData.user) {
    return json(401, { error: 'Your admin session is not valid.' })
  }

  const { data: callerProfile, error: profileError } = await callerClient
    .from('profiles')
    .select('role, status')
    .eq('id', authData.user.id)
    .single()
  if (
    profileError ||
    callerProfile?.role !== 'admin' ||
    callerProfile?.status !== 'approved'
  ) {
    return json(403, { error: 'Only an approved admin can create customer accounts.' })
  }

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch (_) {
    return json(400, { error: 'Invalid request body.' })
  }

  const fullName = String(body.fullName ?? '').trim()
  const username = String(body.username ?? '').trim().toLowerCase()
  const password = String(body.password ?? '')
  const customerId = String(body.customerId ?? '').trim()
  if (!fullName) return json(400, { error: 'Display name is required.' })
  if (!usernamePattern.test(username)) {
    return json(400, {
      error: 'Username must use 3–40 letters, numbers, dots, dashes, or underscores.',
    })
  }
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
  if (!customerId) return json(400, { error: 'Customer assignment is required.' })

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: customer, error: customerError } = await adminClient
    .from('customers')
    .select('id')
    .eq('id', customerId)
    .maybeSingle()
  if (customerError || !customer) {
    return json(400, { error: 'The selected customer no longer exists.' })
  }

  const { data: existingProfile } = await adminClient
    .from('profiles')
    .select('id')
    .eq('username', username)
    .maybeSingle()
  if (existingProfile) {
    return json(409, { error: 'That username is already in use.' })
  }

  const email = `${username}@${customerEmailDomain}`
  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, username },
  })
  if (createError || !created.user) {
    const duplicate = createError?.message.toLowerCase().includes('already')
    return json(duplicate ? 409 : 400, {
      error: duplicate
        ? 'That username is already in use.'
        : (createError?.message ?? 'Could not create the customer account.'),
    })
  }

  const profile = {
    id: created.user.id,
    email,
    username,
    full_name: fullName,
    role: 'customer',
    status: 'approved',
    customer_id: customerId,
  }
  const { error: assignmentError } = await adminClient
    .from('profiles')
    .upsert(profile)
  if (assignmentError) {
    try {
      const { error: cleanupError } = await adminClient.auth.admin.deleteUser(
        created.user.id,
      )
      if (cleanupError) {
        console.error('Customer account rollback failed', cleanupError.message)
        return json(500, {
          error: 'Account assignment failed and cleanup needs administrator attention.',
        })
      }
    } catch (cleanupError) {
      console.error('Customer account rollback failed', cleanupError)
      return json(500, {
        error: 'Account assignment failed and cleanup needs administrator attention.',
      })
    }
    return json(500, { error: 'Account creation was rolled back because assignment failed.' })
  }

  return json(201, { profile })
})
