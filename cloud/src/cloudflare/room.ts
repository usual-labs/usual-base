import { DurableObject } from "cloudflare:workers";
import type { PushedEvent } from "../env";

/**
 * One per Base: holds the WebSockets of every app watching the Base and tells them about each push.
 * Uses WebSocket hibernation, so an idle room costs nothing.
 */
export class BaseRoom extends DurableObject<unknown> {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    // Apps keep their socket alive with "ping"; the runtime answers without waking the object.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return new Response("Expected a WebSocket\n", { status: 426 });
    }
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async broadcast(event: PushedEvent): Promise<void> {
    const message = JSON.stringify(event);
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.send(message);
      } catch {
        // A socket that closed meanwhile; the runtime drops it.
      }
    }
  }

  async webSocketClose(socket: WebSocket, code: number): Promise<void> {
    socket.close(code === 1005 ? 1000 : code, "closing");
  }
}
