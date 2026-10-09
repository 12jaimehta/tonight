import { readFile } from "fs/promises";
import path from "path";
import { uploadPath } from "@/lib/store";

const types: Record<string, string> = {
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
  ".gif": "image/gif",
};

export async function GET(
  _request: Request,
  context: { params: Promise<{ name: string }> },
) {
  const { name } = await context.params;
  if (!/^[\w.-]+$/.test(name)) return new Response("Not found", { status: 404 });
  try {
    const bytes = await readFile(uploadPath(path.basename(name)));
    const ext = path.extname(name).toLowerCase();
    return new Response(bytes, {
      headers: { "Content-Type": types[ext] ?? "application/octet-stream" },
    });
  } catch {
    return new Response("Not found", { status: 404 });
  }
}
