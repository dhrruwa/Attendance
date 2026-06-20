// =====================================================================
// rfid_attendance — FALLBACK attendance via an RFID/NFC reader (ESP8266).
// =====================================================================
// A fixed reader in a room taps a student ID card and reports the SRN printed
// on the card. This is a TEACHER-SUPERVISED fallback for when a student can't
// use the app (no phone / BLE / camera issue). A card scan has NO liveness or
// face check, so every row written here is marked reason='manual_rfid' and is
// fully auditable.
//
// Auth: the device cannot hold a student JWT, so this function runs with
// verify_jwt=false and authenticates the reader by a shared device secret.
//
// Request (GET query params, to match the ESP8266 HTTPClient.GET sketch):
//   ?secret=<RFID_DEVICE_SECRET>&room=<ROOM_CODE>&srn=<student SRN>
// (POST JSON with the same fields also works.)
//
// Resolves the open session for the room, then the student by student_code=srn,
// then upserts a present row (overriding a prior flagged/absent row for that
// student+session — a supervised card tap wins over a failed BLE attempt).
// =====================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.10';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  // Accept params from query string (GET) or JSON body (POST).
  const url = new URL(req.url);
  let p: (k: string) => string = (k) => url.searchParams.get(k) ?? '';
  if (req.method === 'POST') {
    try {
      const body = await req.json();
      p = (k) => (body[k] ?? url.searchParams.get(k) ?? '').toString();
    } catch (_) {
      /* fall back to query params */
    }
  }

  const secret = p('secret');
  const room = p('room').trim();
  const srn = p('srn').trim();

  const expected = Deno.env.get('RFID_DEVICE_SECRET') ?? '';
  if (!expected || secret !== expected) {
    return json({ status: 'error', error: 'unauthorized device' }, 401);
  }
  if (!srn) return json({ status: 'error', error: 'missing srn' }, 400);
  if (!room) return json({ status: 'error', error: 'missing room' }, 400);

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // 1) Student by SRN (== student_code).
  const { data: student } = await admin
    .from('users')
    .select('id, full_name, student_code')
    .eq('student_code', srn)
    .eq('role', 'student')
    .maybeSingle();
  if (!student) {
    return json({ status: 'unknown_card', error: `no student for SRN ${srn}` }, 404);
  }

  // 2) Open session for this room. Prefer a session explicitly tagged with the
  //    room; otherwise fall back to the room->course map (covers app-started
  //    sessions that didn't set a room).
  const nowIso = new Date().toISOString();
  let session: { id: string } | null = null;

  const tagged = await admin
    .from('sessions')
    .select('id')
    .eq('room', room)
    .eq('status', 'open')
    .gt('ends_at', nowIso)
    .order('started_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  session = tagged.data;

  if (!session) {
    const rc = await admin
      .from('room_courses')
      .select('course_id')
      .eq('room', room)
      .maybeSingle();
    if (rc.data) {
      const viaCourse = await admin
        .from('sessions')
        .select('id')
        .eq('course_id', rc.data.course_id)
        .eq('status', 'open')
        .gt('ends_at', nowIso)
        .order('started_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      session = viaCourse.data;
    }
  }

  if (!session) {
    return json(
      { status: 'no_session', name: student.full_name, error: `no open session in ${room}` },
      409,
    );
  }

  // 3) Upsert present. A supervised card tap overrides a prior flagged/absent
  //    row for the same student+session (unique(session_id, student_id)).
  const { error } = await admin.from('attendance').upsert(
    {
      session_id: session.id,
      student_id: student.id,
      status: 'present',
      reason: 'manual_rfid',
      evidence: { source: 'rfid', srn, room },
    },
    { onConflict: 'session_id,student_id' },
  );
  if (error) {
    return json({ status: 'error', error: error.message }, 500);
  }

  return json({ status: 'present', name: student.full_name, srn: student.student_code });
});
