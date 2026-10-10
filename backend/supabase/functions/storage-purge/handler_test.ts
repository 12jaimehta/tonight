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
    bucket: "study-audio",
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
  assertEquals(calls[0].url, "https://project-ref.supabase.co/storage/v1/object/list/study-audio");
  assertEquals(calls[1].method, "DELETE");
  assertEquals(calls[1].url, "https://project-ref.supabase.co/storage/v1/object/study-audio");
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
    bucket: "study-audio",
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

Deno.test("DEL-21 the migration alerts on unfinished rows", async () => {
  const url = new URL("../../migrations/20261010130500_schedule_storage_purge.sql", import.meta.url);
  const sql = await Deno.readTextFile(url);
  assertEquals(sql.includes("deleted_at is null"), true);
  assertEquals(sql.includes("> interval '24 hours'"), true);
  assertEquals(sql.includes("invoke_storage_purge"), true);
  assertEquals(sql.includes("functions/v1/storage-purge"), true);
});

function row(): DeletionQueueRow {
  return { id: "queue-1", bucketId: "study-audio", objectPrefix: "parent/child/" };
}

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}

function assertEquals(actual: unknown, expected: unknown) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) throw new Error(`expected ${right} but got ${left}`);
}
