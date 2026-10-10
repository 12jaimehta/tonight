import { createStorageClient, purgeDue, type DeletionQueueRow, type StorageObject } from "./handler.ts";

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
