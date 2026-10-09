import { forgetWord } from "@/lib/actions";
import { listHomework, listRemember } from "@/lib/store";
import { Say } from "@/components/Say";

export const dynamic = "force-dynamic";

export default function RememberPage() {
  const items = listRemember();
  const titles = new Map(listHomework().map((item) => [item.id, item.instruction]));

  return (
    <div className="space-y-5">
      <div>
        <h1 className="font-[family-name:var(--font-display)] text-4xl">Remember</h1>
        <p className="mt-2 text-[15px] leading-6 text-[#5c564c]">
          Words from earlier pages, kept so they can be heard again.
        </p>
      </div>

      {items.length === 0 ? (
        <p className="rounded-3xl border border-[var(--line)] bg-[var(--card)] p-6 text-[15px]">
          Nothing saved yet. After a mark, choose Remember on a missed word.
        </p>
      ) : (
        <ul className="space-y-3">
          {items.map((item) => (
            <li
              key={item.id}
              className="flex items-center justify-between gap-3 rounded-3xl border border-[var(--line)] bg-[var(--card)] px-4 py-3"
            >
              <div>
                <p className="text-lg">{item.word}</p>
                <p className="text-sm text-[#5c564c]">{titles.get(item.homeworkId) ?? "Earlier page"}</p>
              </div>
              <div className="flex items-center gap-3">
                <Say text={item.word} />
                <form action={forgetWord}>
                  <input type="hidden" name="id" value={item.id} />
                  <button type="submit" className="text-sm text-[#5c564c]">
                    Done
                  </button>
                </form>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
