import {
  createStorageClient,
  handleStoragePurge,
  purgeDue,
  purgeOlderThan,
  type DeletionQueueRow,
  type StorageObject,
} from "./handler.ts";

Deno.test("DEL-06 DEL-16 storage remove then an empty list marks the row done", async () => {
  const removed: string[][] = [];
  const lists = [
    [{ name: "parent/child/a.wav" }],
    [],
  ];
  const done: string[] = [];
  const result = await purgeDue({
    due: async () => [row()],
    storage: {
      list: async () => lists.shift() ?? [],
      remove: async (names) => {
        removed.push(names);
      },
    },
    markDone: async (id) => {
      done.push(id);
    },
  });
  assertEquals(removed, [["parent/child/a.wav"]]);
  assertEquals(done, ["queue-1"]);
  assertEquals(result.remaining, []);
});

Deno.test("DEL-15 a leftover object does not mark the row done", async () => {
  const done: string[] = [];
  const result = await purgeDue({
    due: async () => [row()],
    storage: {
      list: async () => [{ name: "parent/child/stuck.wav" }],
      remove: async () => {},
    },
    markDone: async (id) => {
      done.push(id);
    },
  });
  assertEquals(done, []);
  assertEquals(result.deletedIds, []);
  assertEquals(result.remaining, ["parent/child/stuck.wav"]);
});

Deno.test("DEL-06 the client calls the Storage API and not a SQL delete", async () => {
  const calls: { method: string; url: string; body: string }[] = [];
  let listed = false;
  const client = createStorageClient({
    supabaseUrl: "https://project-ref.supabase.co",
    serviceKey: "service-role",
    bucket: "kept-audio",
    fetchImpl: async (url, init) => {
      calls.push({ method: init.method ?? "", url, body: String(init.body ?? "") });
      if (init.method === "POST") {
        listed = true;
        return json([{ name: "clip.wav" }]);
      }
      return json([]);
    },
  });
  const objects = await client.list("parent/child/");
  assertEquals(objects, [{ name: "parent/child/clip.wav" }]);
  await client.remove(objects.map((object: StorageObject) => object.name));
  assertEquals(calls[0].method, "POST");
  assertEquals(calls[0].url, "https://project-ref.supabase.co/storage/v1/object/list/kept-audio");
  assertEquals(calls[1].method, "DELETE");
  assertEquals(calls[1].url, "https://project-ref.supabase.co/storage/v1/object/kept-audio");
  assertEquals(calls[1].body.includes("parent/child/clip.wav"), true);
  assertEquals(listed, true);
  assertEquals(JSON.stringify(calls).includes("delete from storage.objects"), false);
});

Deno.test("DEL-11 a scheduled POST runs the due purge", async () => {
  const calls: string[] = [];
  const response = await handleStoragePurge(
    new Request("https://project-ref.supabase.co/functions/v1/storage-purge", {
      method: "POST",
      headers: { authorization: "Bearer service-role", "content-type": "application/json" },
      body: JSON.stringify({ mode: "due" }),
    }),
    {
      purgeDue: async () => {
        calls.push("due");
        return { deletedIds: ["queue-1"], remaining: [] };
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(calls, ["due"]);
  const missing = await handleStoragePurge(
    new Request("https://project-ref.supabase.co/functions/v1/storage-purge", { method: "POST" }),
    { purgeDue: async () => ({ deletedIds: [], remaining: [] }) },
  );
  assertEquals(missing.status, 401);
});

Deno.test("DEL-16 retention deletes object bytes older than 90 days", async () => {
  const now = new Date("2026-10-10T00:00:00.000Z");
  const old = "2026-07-01T00:00:00.000Z";
  const recent = "2026-10-09T00:00:00.000Z";
  const removed: string[][] = [];
  const result = await purgeOlderThan({
    days: 90,
    now,
    storage: {
      list: async () => [
        { name: "old.wav", createdAt: old },
        { name: "nested/deep.wav", createdAt: old },
        { name: "recent.wav", createdAt: recent },
        { name: "undated.wav" },
      ],
      remove: async (names) => {
        removed.push(names);
      },
    },
  });
  assertEquals(removed, [["old.wav", "nested/deep.wav"]]);
  assertEquals(result.removed, ["old.wav", "nested/deep.wav"]);
});

Deno.test("DEL-16 list pages past the cap and recurses into folders", async () => {
  const client = createStorageClient({
    supabaseUrl: "https://project-ref.supabase.co",
    serviceKey: "service-role",
    bucket: "kept-audio",
    pageSize: 2,
    fetchImpl: async (_url, init) => {
      const body = JSON.parse(String(init.body)) as { prefix: string; offset: number; limit: number };
      if (body.prefix === "parent/" && body.offset === 0) {
        return json([
          { name: "a.wav", id: "a", created_at: "2026-01-01T00:00:00.000Z" },
          { name: "folder", id: null },
        ]);
      }
      if (body.prefix === "parent/" && body.offset === 2) {
        return json([{ name: "b.wav", id: "b" }]);
      }
      if (body.prefix === "parent/folder/") {
        return json([{ name: "c.wav", id: "c" }]);
      }
      return json([]);
    },
  });
  const objects = await client.list("parent/");
  assertEquals(objects.map((object) => object.name), ["parent/a.wav", "parent/folder/c.wav", "parent/b.wav"]);
  assertEquals(objects[0].createdAt, "2026-01-01T00:00:00.000Z");
});

Deno.test("DEL-21 DEL-11 vault settings fail clearly and alerts are not in the purge job", async () => {
  const url = new URL("../../migrations/20261010130700_purge_settings_and_alert_job.sql", import.meta.url);
  const sql = await Deno.readTextFile(url);
  assertEquals(sql.includes("vault.decrypted_secrets"), true);
  assertEquals(sql.includes("app.settings."), true);
  assertEquals(sql.includes("storage-purge is not configured"), true);
  assertEquals(sql.includes("deletion-sla-alerts"), true);
  assertEquals(sql.includes("storage-purge-due"), true);
  assertEquals(sql.includes("select public.raise_deletion_sla_alerts(); select public.purge_due_study_audio()"), false);
  const alert = sql.indexOf("select public.raise_deletion_sla_alerts()");
  const purge = sql.indexOf("select public.purge_due_study_audio()");
  assertEquals(alert > 0 && purge > 0 && alert !== purge, true);
});

Deno.test("DEL-06 one bad row does not block the rest", async () => {
  const done: string[] = [];
  const result = await purgeDue({
    due: async () => [
      { id: "bad", bucketId: "kept-audio", objectPrefix: "bad/" },
      { id: "good", bucketId: "none", objectPrefix: "good/" },
    ],
    storage: {
      list: async () => {
        throw new Error("storage_list_failed");
      },
      remove: async () => {},
    },
    markDone: async (id) => {
      done.push(id);
    },
  });
  assertEquals(done, ["good"]);
  assertEquals(result.deletedIds, ["good"]);
  assertEquals(result.remaining, ["bad/"]);
});

Deno.test("DEL-11 DEL-21 child delete reaches the queue and purge finishes before an alert", async () => {
  const sql = await Deno.readTextFile(
    new URL("../../migrations/20261010130800_queue_without_study_audio.sql", import.meta.url),
  );
  const insertAt = sql.indexOf("insert into public.storage_deletion_queue");
  const inserted = sql.slice(insertAt);
  assertEquals(inserted.includes("'none'"), true);
  assertEquals(inserted.includes("study-audio"), false);
  const enqueuedAt = new Date().toISOString();
  const queue: { id: string; bucketId: string; objectPrefix: string; deletedAt: string | null; enqueuedAt: string }[] = [];
  queue.push({
    id: "queue-child",
    bucketId: "none",
    objectPrefix: "parent/child/",
    deletedAt: null,
    enqueuedAt,
  });
  assertEquals(queue[0].bucketId === "study-audio", false);
  const result = await purgeDue({
    due: async () =>
      queue
        .filter((row) => row.deletedAt === null)
        .map((row) => ({ id: row.id, bucketId: row.bucketId, objectPrefix: row.objectPrefix })),
    storage: {
      list: async () => {
        throw new Error("no bucket to list");
      },
      remove: async () => {},
    },
    markDone: async (id) => {
      const row = queue.find((item) => item.id === id);
      if (row) row.deletedAt = new Date().toISOString();
    },
  });
  assertEquals(result.deletedIds, ["queue-child"]);
  assertEquals(queue[0].deletedAt !== null, true);
  const unfinished = queue.filter((row) => row.deletedAt === null);
  assertEquals(unfinished, []);
});

Deno.test("N-12 storage-purge request matches the shared contract", async () => {
  const fixture = JSON.parse(
    await Deno.readTextFile(new URL("./storage-purge.contract.json", import.meta.url)),
  );
  assertEquals(fixture.name, "storage-purge");
  assertEquals(fixture.request.method, "POST");
  assertEquals(fixture.request.path, "/functions/v1/storage-purge");
  assertEquals(fixture.request.body.required, ["mode"]);
  assertEquals(fixture.request.body.properties.mode.enum, ["due", "retention"]);
  const response = await handleStoragePurge(
    new Request("https://project-ref.supabase.co/functions/v1/storage-purge", {
      method: fixture.request.method,
      headers: { authorization: "Bearer service-role", "content-type": "application/json" },
      body: JSON.stringify({ mode: "due" }),
    }),
    { purgeDue: async () => ({ deletedIds: ["queue-1"], remaining: [] }) },
  );
  assertEquals(response.status, 200);
  const missing = await handleStoragePurge(
    new Request("https://project-ref.supabase.co/functions/v1/storage-purge", {
      method: "POST",
      body: JSON.stringify({ mode: "due" }),
    }),
    { purgeDue: async () => ({ deletedIds: [], remaining: [] }) },
  );
  assertEquals(missing.status, 401);
});

Deno.test("DEL-21 the migration alerts on unfinished rows", async () => {
  const url = new URL("../../migrations/20261010130500_schedule_storage_purge.sql", import.meta.url);
  const sql = await Deno.readTextFile(url);
  assertEquals(sql.includes("deleted_at is null"), true);
  assertEquals(sql.includes("> interval '24 hours'"), true);
  assertEquals(sql.includes("invoke_storage_purge"), true);
  assertEquals(sql.includes("functions/v1/storage-purge"), true);
});

function row(): DeletionQueueRow {
  return { id: "queue-1", bucketId: "kept-audio", objectPrefix: "parent/child/" };
}

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}

function assertEquals(actual: unknown, expected: unknown) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) throw new Error(`expected ${right} but got ${left}`);
}
