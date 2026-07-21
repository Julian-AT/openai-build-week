import { notFound } from "next/navigation";

import { assertReplaySessionID } from "../../../lib/replay-data.ts";
import ReplaySurface from "./replay-surface.tsx";

export default async function ReplayPage({ params }: { params: Promise<{ sessionID: string }> }) {
  const { sessionID } = await params;
  try {
    assertReplaySessionID(sessionID);
  } catch {
    notFound();
  }
  return <ReplaySurface sessionID={sessionID} />;
}
