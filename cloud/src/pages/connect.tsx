import type { Base } from "../bases";
import type { User } from "../env";
import { BaseChoice } from "./agents";
import { ErrorNote, Icon, Page } from "./layout";

export function EnterCode(props: { user: User; error?: string }) {
  return (
    <Page title="Approve a connection" user={props.user} narrow>
      <div class="panel">
        <div class="status-mark"><Icon name="key" /></div>
        <h1>Approve a connection</h1>
        <p class="lead">Enter the code the app or agent shows you.</p>
        <form class="form" method="get" action="/connect">
          <label class="field">
            <span>Code</span>
            <input class="code-input" type="text" name="code" required autocomplete="off" autocapitalize="characters"
              spellcheck={false} placeholder="ABCD-EFGH" autofocus />
          </label>
          {props.error && <ErrorNote>{props.error}</ErrorNote>}
          <button class="block" type="submit">Continue</button>
        </form>
      </div>
    </Page>
  );
}

export function Approve(props: {
  user: User;
  code: string;
  clientName: string;
  kind: "agent" | "device";
  bases: Base[];
}) {
  return (
    <Page title="Approve a connection" user={props.user} narrow>
      <div class="panel">
        <h1>Connect “{props.clientName}”?</h1>
        <p class="lead">Check that the {props.kind === "device" ? "app" : "agent"} shows this code:</p>
        <div class="spaced-sm"><span class="code-display">{props.code}</span></div>
        <form class="form" method="post" action="/connect">
          <input type="hidden" name="code" value={props.code} />
          {props.kind === "device" ? (
            <p class="notice"><Icon name="laptop" size={16} /><span>This device gets read and write access to all your Bases.</span></p>
          ) : (
            <>
              <BaseChoice bases={props.bases} />
              <label class="check"><input type="checkbox" name="write" value="1" checked /> Can write</label>
            </>
          )}
          <div class="actions">
            <button class="grow" type="submit" name="decision" value="approve">Approve</button>
            <button class="secondary grow" type="submit" name="decision" value="deny">Deny</button>
          </div>
        </form>
      </div>
    </Page>
  );
}

export function Decided(props: { user: User; approved: boolean }) {
  return (
    <Page title="Connection" user={props.user} narrow>
      <div class="panel">
        <div class={`status-mark ${props.approved ? "ok" : ""}`}><Icon name={props.approved ? "check" : "close"} /></div>
        <h1>{props.approved ? "Connected" : "Denied"}</h1>
        <p class="lead">
          {props.approved ? "You can go back to the app or agent; it carries on by itself." : "The app or agent didn't get access."}
        </p>
        <div class="actions spaced">
          <a class="button secondary" href="/agents">See your agents</a>
        </div>
      </div>
    </Page>
  );
}
