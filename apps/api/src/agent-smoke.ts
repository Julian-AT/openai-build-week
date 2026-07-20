import { runLivePlacementAgentSmokeFromEnvironment } from "./live-placement-agent-smoke.ts";

const controller = new AbortController();
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () =>
    controller.abort(new DOMException("operator cancelled", "AbortError")),
  );
}

try {
  const preview = await runLivePlacementAgentSmokeFromEnvironment(process.env, controller.signal);
  process.stdout.write(
    `${JSON.stringify({
      type: preview.type,
      status: preview.status,
      proposal_id: preview.proposal_id,
      base_scene_revision: preview.base_scene_revision,
      asset_id: preview.intent.asset_id,
      model: preview.model,
    })}\n`,
  );
} catch {
  process.stderr.write(`${JSON.stringify({ event: "agent_placement_smoke_failed" })}\n`);
  process.exitCode = 1;
}
