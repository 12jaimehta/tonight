import Link from "next/link";
import { deleteHomework, toggleMarks } from "@/lib/actions";
import { listHomework } from "@/lib/store";

export const dynamic = "force-dynamic";

export default function HomePage() {
  const homework = listHomework();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="font-[family-name:var(--font-display)] text-4xl leading-tight">
          Tonight&apos;s page
        </h1>
        <p className="mt-2 text-[15px] leading-6 text-[#5c564c]">
          Upload the school page. Your child hears it, reads it, and gets a mark counted from the words.
        </p>
      </div>

      {homework.length === 0 ? (
        <div className="rounded-3xl border border-[var(--line)] bg-[var(--card)] p-6">
          <p className="text-[15px] leading-6">Nothing is set for today.</p>
          <Link
            href="/new"
            className="mt-4 inline-flex rounded-full bg-[var(--green)] px-4 py-2 text-sm text-white"
          >
            Add the page
          </Link>
        </div>
      ) : (
        <ul className="space-y-4">
          {homework.map((item) => {
            const latest = item.attempts[item.attempts.length - 1];
            return (
              <li key={item.id} className="overflow-hidden rounded-3xl border border-[var(--line)] bg-[var(--card)]">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`/file/${item.image}`} alt="" className="h-40 w-full object-cover" />
                <div className="space-y-3 p-5">
                  <p className="text-lg leading-6">{item.instruction}</p>
                  <p className="text-sm text-[#5c564c]">
                    {latest
                      ? `Last mark ${latest.correct} of ${latest.total} words`
                      : "Not attempted yet"}
                  </p>
                  <form action={toggleMarks} className="flex items-center gap-2 text-sm">
                    <input type="hidden" name="id" value={item.id} />
                    <input
                      id={`marks-${item.id}`}
                      name="showMarks"
                      type="checkbox"
                      defaultChecked={item.showMarksToChild}
                      className="size-4"
                    />
                    <label htmlFor={`marks-${item.id}`}>Child can see the mark</label>
                    <button className="ml-auto text-[var(--green)]" type="submit">
                      Save
                    </button>
                  </form>
                  <div className="flex items-center gap-3">
                    <Link
                      href={`/h/${item.id}`}
                      className="rounded-full bg-[var(--green)] px-4 py-2 text-sm text-white"
                    >
                      Child starts
                    </Link>
                    <form action={deleteHomework}>
                      <input type="hidden" name="id" value={item.id} />
                      <button className="text-sm text-[#5c564c]" type="submit">
                        Remove
                      </button>
                    </form>
                  </div>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
