// Deletes study-audio object bytes through the Storage API. A queue row is
// finished only after a follow-up list for that prefix is empty.

export type StorageObject = { name: string };

export type StorageClient = {
  list(prefix: string): Promise<StorageObject[]>;
  remove(names: string[]): Promise<void>;
};

export type DeletionQueueRow = {
  id: string;
  bucketId: string;
  objectPrefix: string;
};

export type PurgeDeps = {
  due: () => Promise<DeletionQueueRow[]>;
  storage: StorageClient;
  markDone: (id: string) => Promise<void>;
};

export type PurgeResult = {
  deletedIds: string[];
  remaining: string[];
};

export async function purgeDue(deps: PurgeDeps): Promise<PurgeResult> {
  const deletedIds: string[] = [];
  const remaining: string[] = [];
  for (const row of await deps.due()) {
    const names = (await deps.storage.list(row.objectPrefix)).map((object) => object.name);
    if (names.length > 0) {
      await deps.storage.remove(names);
    }
    const after = await deps.storage.list(row.objectPrefix);
    if (after.length > 0) {
      remaining.push(...after.map((object) => object.name));
      continue;
    }
    await deps.markDone(row.id);
    deletedIds.push(row.id);
  }
  return { deletedIds, remaining };
}

type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

export function createStorageClient(deps: {
  supabaseUrl: string;
  serviceKey: string;
  bucket: string;
  fetchImpl: FetchLike;
}): StorageClient {
  const headers = {
    authorization: `Bearer ${deps.serviceKey}`,
    apikey: deps.serviceKey,
    "content-type": "application/json",
  };
  return {
    async list(prefix) {
      const response = await deps.fetchImpl(
        `${deps.supabaseUrl}/storage/v1/object/list/${deps.bucket}`,
        { method: "POST", headers, body: JSON.stringify({ prefix, limit: 1000 }) },
      );
      if (!response.ok) throw new Error("storage_list_failed");
      const rows = await response.json();
      if (!Array.isArray(rows)) return [];
      return rows.flatMap((row) => {
        if (!row || typeof row !== "object" || typeof (row as { name?: unknown }).name !== "string") return [];
        return [{ name: prefix + (row as { name: string }).name }];
      });
    },
    async remove(names) {
      if (names.length === 0) return;
      const response = await deps.fetchImpl(
        `${deps.supabaseUrl}/storage/v1/object/${deps.bucket}`,
        { method: "DELETE", headers, body: JSON.stringify(names) },
      );
      if (!response.ok) throw new Error("storage_remove_failed");
      await response.body?.cancel();
    },
  };
}
