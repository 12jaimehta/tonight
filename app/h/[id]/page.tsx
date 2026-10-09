import Link from "next/link";
import { notFound } from "next/navigation";
import { ChildSession } from "@/components/ChildSession";
import { getHomework } from "@/lib/store";

export const dynamic = "force-dynamic";

export default async function HomeworkPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const homework = getHomework(id);
  if (!homework) notFound();

  return (
    <div className="space-y-4">
      <Link href="/" className="text-sm text-[#5c564c]">
        Back to today
      </Link>
      <ChildSession
        id={homework.id}
        instruction={homework.instruction}
        passage={homework.passage}
        image={homework.image}
        showMarksToChild={homework.showMarksToChild}
      />
    </div>
  );
}
