/// Build an SSE response stream that the iOS client consumes. Only two
/// event types are emitted — `guess` and `final` — so the channel is
/// narrow enough that a stolen App Attest assertion can't smuggle
/// arbitrary model text out.

export type DownstreamEvent =
  | { type: "guess"; text: string }
  | { type: "final"; guess: string }
  | { type: "giveUp" };

export function makeSSEResponse(
  pump: (emit: (event: DownstreamEvent) => void) => Promise<void>
): Response {
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emit = (event: DownstreamEvent) => {
        const name = event.type;
        const data = JSON.stringify(event.type === "guess"
          ? { text: event.text }
          : event.type === "final"
            ? { guess: event.guess }
            : {});
        controller.enqueue(encoder.encode(`event: ${name}\ndata: ${data}\n\n`));
      };
      try {
        await pump(emit);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        const data = JSON.stringify({ message: msg });
        controller.enqueue(encoder.encode(`event: error\ndata: ${data}\n\n`));
      } finally {
        controller.close();
      }
    },
  });
  return new Response(stream, {
    status: 200,
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-store",
      "x-accel-buffering": "no",
    },
  });
}
