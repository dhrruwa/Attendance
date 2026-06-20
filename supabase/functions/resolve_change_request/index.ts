// =====================================================================
// resolve_change_request — teacher approves/rejects a profile change request.
// =====================================================================
// Approving opens a one-shot edit window (users.edit_allowed=true) for the
// student; the DB trigger re-locks it after the student's next save. Only a
// teacher who actually teaches the student may resolve a request — verified
// here server-side with the service role.
//
// Request (POST JSON):  { request_id: uuid, approve: boolean }
// Auth: the teacher's JWT (verify_jwt=true).
// =====================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.10';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const url = Deno.env.get('SUPABASE_URL')!;
  const authHeader = req.headers.get('Authorization') ?? '';

  // Caller identity from their JWT.
  const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: who } = await asUser.auth.getUser();
  const callerId = who.user?.id;
  if (!callerId) return json({ error: 'unauthenticated' }, 401);

  let body: { request_id?: string; approve?: boolean };
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: 'invalid body' }, 400);
  }
  const requestId = body.request_id;
  const approve = body.approve === true;
  if (!requestId) return json({ error: 'missing request_id' }, 400);

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  // Load the request.
  const { data: reqRow } = await admin
    .from('profile_change_requests')
    .select('id, student_id, status')
    .eq('id', requestId)
    .maybeSingle();
  if (!reqRow) return json({ error: 'request not found' }, 404);
  if (reqRow.status !== 'pending') {
    return json({ error: `request already ${reqRow.status}` }, 409);
  }

  // Verify the caller teaches this student.
  const courses = await admin.from('courses').select('id').eq('teacher_id', callerId);
  const courseIds = (courses.data ?? []).map((c) => c.id);
  let teaches = false;
  if (courseIds.length > 0) {
    const enr = await admin
      .from('enrollments')
      .select('id')
      .eq('student_id', reqRow.student_id)
      .in('course_id', courseIds)
      .limit(1);
    teaches = (enr.data ?? []).length > 0;
  }
  if (!teaches) return json({ error: 'not your student' }, 403);

  // Resolve.
  await admin
    .from('profile_change_requests')
    .update({
      status: approve ? 'approved' : 'rejected',
      resolved_at: new Date().toISOString(),
      resolved_by: callerId,
    })
    .eq('id', requestId);

  if (approve) {
    // Open the one-shot edit window (trigger allows service_role to set this).
    await admin.from('users').update({ edit_allowed: true }).eq('id', reqRow.student_id);
  }

  return json({ status: approve ? 'approved' : 'rejected' });
});
