import { createHomework } from "@/lib/actions";

export default async function NewPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <form action={createHomework} className="space-y-5">
      <div>
        <h1 className="font-[family-name:var(--font-display)] text-4xl">Add today&apos;s page</h1>
        <p className="mt-2 text-[15px] leading-6 text-[#5c564c]">
          The photo is what your child sees. The lines below are what the mark is counted against.
        </p>
      </div>

      {error === "missing" && (
        <p className="rounded-2xl bg-[var(--miss-soft)] px-4 py-3 text-sm text-[var(--miss)]">
          Add the task, the lines to mark, and a photo of the page.
        </p>
      )}
      {error === "image" && (
        <p className="rounded-2xl bg-[var(--miss-soft)] px-4 py-3 text-sm text-[var(--miss)]">
          Use a JPG, PNG, or WEBP photo.
        </p>
      )}

      <label className="block space-y-2">
        <span className="text-sm">What should be done today</span>
        <input
          name="instruction"
          required
          placeholder="Read the paragraph on plants"
          className="w-full rounded-2xl border border-[var(--line)] bg-white px-4 py-3"
        />
      </label>

      <label className="block space-y-2">
        <span className="text-sm">Lines on the page</span>
        <textarea
          name="passage"
          required
          rows={7}
          placeholder="Paste or type the paragraph, sums, or words to be marked."
          className="w-full rounded-2xl border border-[var(--line)] bg-white px-4 py-3 leading-6"
        />
      </label>

      <label className="block space-y-2">
        <span className="text-sm">Photo of the page</span>
        <input
          name="image"
          type="file"
          accept="image/jpeg,image/png,image/webp,image/gif"
          required
          className="w-full text-sm"
        />
      </label>

      <label className="flex items-center gap-2 text-sm">
        <input name="showMarks" type="checkbox" defaultChecked className="size-4" />
        Child can see the mark
      </label>

      <button type="submit" className="rounded-full bg-[var(--green)] px-5 py-3 text-white">
        Save for tonight
      </button>
    </form>
  );
}
