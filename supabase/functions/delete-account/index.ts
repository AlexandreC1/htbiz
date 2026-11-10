import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

// Permanently deletes the account of the caller.
//
// Deploy WITH JWT verification (the default):
//   supabase functions deploy delete-account
//
// The account to delete is always the one the JWT belongs to. Nothing in the
// request body is read, so a caller cannot name somebody else's account.
//
// Order matters:
//   1. Storage files first. They are not tied to the user by a foreign key,
//      so once the user row is gone nothing would lead back to them. If any
//      file cannot be removed the function stops and the account is left
//      intact, and the user can simply try again.
//   2. The auth user last. Every table that belongs to the user follows that
//      delete through ON DELETE CASCADE (see
//      supabase/migrations/20261111000000_account_deletion.sql), including
//      the businesses they own and the reviews other people left on those
//      businesses.

// The storage API of a client. Taken from createClient so that it does not
// depend on the generic parameters of SupabaseClient.
type StorageApi = ReturnType<typeof createClient>["storage"];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

// Where a user's files live. Every path starts with a folder named after the
// user id, which is also what the storage policies enforce on upload.
const userFolders = (userId: string): { bucket: string; folder: string }[] => [
  { bucket: "htbiz_images", folder: `businesses/${userId}` },
  { bucket: "htbiz_images", folder: `reviews/${userId}` },
  { bucket: "htbiz_images", folder: `avatars/${userId}` },
  { bucket: "htbiz_patents", folder: userId },
];

const PAGE_SIZE = 100;
const MAX_DEPTH = 6;
const MAX_FILES = 20000;

/** Every file below `folder`, following sub folders, one page at a time. */
async function listFiles(
  storage: StorageApi,
  bucket: string,
  folder: string,
  depth = 0,
): Promise<string[]> {
  const files: string[] = [];
  if (depth > MAX_DEPTH) return files;

  for (let offset = 0; ; offset += PAGE_SIZE) {
    const { data, error } = await storage.from(bucket).list(folder, {
      limit: PAGE_SIZE,
      offset,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw new Error(`list ${bucket}/${folder}: ${error.message}`);
    const entries = data ?? [];

    for (const entry of entries) {
      const path = `${folder}/${entry.name}`;
      // The storage API reports a sub folder as an entry without an id.
      if (entry.id == null) {
        files.push(...await listFiles(storage, bucket, path, depth + 1));
      } else {
        files.push(path);
      }
      if (files.length > MAX_FILES) {
        throw new Error(`more than ${MAX_FILES} files under ${bucket}/${folder}`);
      }
    }

    if (entries.length < PAGE_SIZE) break;
  }
  return files;
}

/** Removes every file of the user from both buckets. Returns the count. */
async function removeUserFiles(
  storage: StorageApi,
  userId: string,
): Promise<number> {
  let removed = 0;
  for (const { bucket, folder } of userFolders(userId)) {
    // The listing is complete before anything is removed, so the offsets
    // above never skip a file because an earlier page shrank.
    const files = await listFiles(storage, bucket, folder);
    for (let i = 0; i < files.length; i += PAGE_SIZE) {
      const batch = files.slice(i, i + PAGE_SIZE);
      const { error } = await storage.from(bucket).remove(batch);
      if (error) throw new Error(`remove from ${bucket}: ${error.message}`);
      removed += batch.length;
    }
  }
  return removed;
}

serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed", code: "method_not_allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Auth check: the account is identified by the JWT and by nothing else.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "No authorization header", code: "unauthorized" }, 401);
    }

    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();

    if (userError || !user) {
      return json({ error: "Unauthorized", code: "unauthorized" }, 401);
    }

    // Service role client: bypasses RLS and may call the auth admin API.
    const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    let filesRemoved = 0;
    try {
      filesRemoved = await removeUserFiles(adminClient.storage, user.id);
    } catch (err) {
      console.error("delete-account storage error", user.id, err);
      return json({
        error: "Your files could not be removed. Your account was not deleted. Please try again.",
        code: "storage_cleanup_failed",
      }, 500);
    }

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id);
    if (deleteError) {
      console.error("delete-account auth error", user.id, deleteError);
      return json({
        error: "Your account could not be deleted. Please try again.",
        code: "delete_failed",
      }, 500);
    }

    console.log("delete-account done", user.id, "files removed:", filesRemoved);
    return json({ success: true, files_removed: filesRemoved }, 200);
  } catch (err) {
    // Never echo err.message: it can carry table or constraint names.
    console.error("delete-account error", err);
    return json({ error: "Internal error", code: "internal_error" }, 500);
  }
});
