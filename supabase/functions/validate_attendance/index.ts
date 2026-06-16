// =====================================================================
// validate_attendance — the ONLY place attendance is decided.
// =====================================================================
// The phone reports observations (the evidence object). This function, running
// with the service role, decides present|flagged and writes the authoritative
// row. It verifies, in order:
//   1. caller identity (JWT) and enrollment in the session's course
//   2. session is open and within its time window
//   3. the submitted BLE token exists for this session and is within its window
//   4. the device id matches the student's bound active device
//   5. the evidence shows face-match + liveness (passive + active) passed
//   6. proximity (RSSI) is plausible
// then dedupes (one row per student per session) and returns the verdict.
// =====================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.10';

// ---- Tunable server-side policy thresholds --------------------------
const FACE_MATCH_MIN = 0.75; // cosine similarity to enrolled embedding
const PASSIVE_SPOOF_MIN = 0.70; // passive anti-spoof model score
const RSSI_MIN = -85; // dBm; weaker => too far from teacher => flag
const TOKEN_SKEW_MS = 3000; // tolerance on token validity window

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

interface Evidence {
  face_match_score: number;
  liveness_passed: boolean;
  challenge_type: string;
  challenge_passed?: boolean;
  passive_spoof_score?: number | null;
  ble_token: string;
  rssi: number;
  device_id: string;
  [k: string]: unknown;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'method not allowed' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;

  // 1. Identify the caller from their JWT (anon client bound to the token).
  const authHeader = req.headers.get('Authorization') ?? '';
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: 'unauthenticated' }, 401);
  }
  const studentId = userData.user.id;

  // Parse body.
  let body: { session_id?: string; evidence?: Evidence };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid json' }, 400);
  }
  const sessionId = body.session_id;
  const evidence = body.evidence;
  if (!sessionId || !evidence) {
    return json({ error: 'session_id and evidence are required' }, 400);
  }

  // Service-role client: bypasses RLS to read tokens/devices and write the row.
  const admin = createClient(supabaseUrl, serviceKey);
  const now = Date.now();

  // 2. Session must exist, be open, and within its window.
  const { data: session, error: sErr } = await admin
    .from('sessions')
    .select('id, course_id, status, started_at, ends_at')
    .eq('id', sessionId)
    .maybeSingle();
  if (sErr) return json({ error: 'session lookup failed' }, 500);
  if (!session) return json({ error: 'session not found' }, 404);

  // Enrollment check — the student must belong to the session's course.
  const { data: enrollment } = await admin
    .from('enrollments')
    .select('id')
    .eq('course_id', session.course_id)
    .eq('student_id', studentId)
    .maybeSingle();
  if (!enrollment) {
    return json({ error: 'not enrolled in this course' }, 403);
  }

  const sessionOpen =
    session.status === 'open' && now <= Date.parse(session.ends_at);

  // 3. Token must exist for this session and be valid now.
  const { data: tokenRow } = await admin
    .from('session_tokens')
    .select('id, valid_from, valid_to')
    .eq('session_id', sessionId)
    .eq('token', evidence.ble_token)
    .maybeSingle();
  const tokenValid =
    !!tokenRow &&
    now >= Date.parse(tokenRow.valid_from) - TOKEN_SKEW_MS &&
    now <= Date.parse(tokenRow.valid_to) + TOKEN_SKEW_MS;

  // 4. Device binding must match the student's active device.
  const { data: device } = await admin
    .from('devices')
    .select('device_id')
    .eq('user_id', studentId)
    .eq('active', true)
    .maybeSingle();
  const deviceMatches = !!device && device.device_id === evidence.device_id;

  // 5. Face + liveness checks from the evidence.
  const faceOk = (evidence.face_match_score ?? 0) >= FACE_MATCH_MIN;
  const livenessOk =
    evidence.liveness_passed === true &&
    evidence.challenge_passed !== false &&
    (evidence.passive_spoof_score == null ||
      evidence.passive_spoof_score >= PASSIVE_SPOOF_MIN);

  // 6. Proximity.
  const rssiOk =
    typeof evidence.rssi === 'number' && evidence.rssi >= RSSI_MIN;

  // ---- Decide -------------------------------------------------------
  const reasons: string[] = [];
  if (!sessionOpen) reasons.push('session not open');
  if (!tokenValid) reasons.push('ble token invalid or expired');
  if (!deviceMatches) reasons.push('device not bound / mismatch');
  if (!faceOk) reasons.push('face match below threshold');
  if (!livenessOk) reasons.push('liveness check failed');
  if (!rssiOk) reasons.push('too far from teacher (weak signal)');

  const present = reasons.length === 0;
  const status = present ? 'present' : 'flagged';
  const reason = present ? 'all checks passed' : reasons.join('; ');

  // ---- Dedupe + persist (one row per student per session) -----------
  const { data: existing } = await admin
    .from('attendance')
    .select('id, status')
    .eq('session_id', sessionId)
    .eq('student_id', studentId)
    .maybeSingle();

  // Never downgrade an already-present row (idempotent re-submits).
  if (existing && existing.status === 'present') {
    return json({
      status: 'present',
      reason: 'already marked present',
      attendance_id: existing.id,
    });
  }

  const row = {
    session_id: sessionId,
    student_id: studentId,
    status,
    evidence,
    submitted_token: evidence.ble_token,
    rssi: evidence.rssi,
    device_id: evidence.device_id,
    reason,
  };

  let attendanceId = existing?.id;
  if (existing) {
    const { error: upErr } = await admin
      .from('attendance')
      .update(row)
      .eq('id', existing.id);
    if (upErr) return json({ error: 'failed to update attendance' }, 500);
  } else {
    const { data: inserted, error: insErr } = await admin
      .from('attendance')
      .insert(row)
      .select('id')
      .single();
    if (insErr) return json({ error: 'failed to record attendance' }, 500);
    attendanceId = inserted.id;
  }

  return json({ status, reason, attendance_id: attendanceId });
});
