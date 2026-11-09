import type { Base } from "../bases";
import type { User } from "../env";
import { BaseChoice } from "./agents";
import { Page } from "./layout";

export function EnterCode(props: { user: User; error?: string }) {
  return (
    <Page title="Approve a connection" user={props.user}>
      <h1>Approve a connection</h1>
      <form class="stack" method="get" action="/connect">
        <label>Code shown by the app or agent<input type="text" name="code" required autocomplete="off" /></label>
        {props.error && <p class="error">{props.error}</p>}
        <div><button type="submit">Continue</button></div>
      </form>
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
    <Page title="Approve a connection" user={props.user}>
      <h1>Connect “{props.clientName}”?</h1>
      <p>
        Check that the app or agent shows this code: <span class="code">{props.code}</span>
      </p>
      <form class="stack" method="post" action="/connect">
        <input type="hidden" name="code" value={props.code} />
        {props.kind === "device" ? (
          <p class="muted">This device gets read and write access to all your Bases.</p>
        ) : (
          <>
            <BaseChoice bases={props.bases} />
            <label class="inline"><input type="checkbox" name="write" value="1" checked /> Can write</label>
          </>
        )}
        <div class="row" style="justify-content:flex-start">
          <button type="submit" name="decision" value="approve">Approve</button>
          <button class="secondary" type="submit" name="decision" value="deny">Deny</button>
        </div>
      </form>
    </Page>
  );
}

export function Decided(props: { user: User; approved: boolean }) {
  return (
    <Page title="Connection" user={props.user}>
      <h1>{props.approved ? "Connected" : "Denied"}</h1>
      <p>{props.approved ? "You can go back to the app or agent." : "The app or agent didn't get access."}</p>
    </Page>
  );
}
