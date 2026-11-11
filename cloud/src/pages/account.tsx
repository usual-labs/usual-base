import type { User } from "../env";
import { AppMark, ErrorNote, Icon, Page } from "./layout";

export function SignIn(props: { next: string; error?: string; email?: string }) {
  return (
    <Page title="Sign in" narrow>
      <div class="panel">
        <h1>Sign in</h1>
        <p class="lead">To your Bases and the agents that use them.</p>
        <form class="form" method="post" action="/sign-in">
          <input type="hidden" name="next" value={props.next} />
          <label class="field">
            <span>Email</span>
            <input type="email" name="email" autocomplete="email" required autofocus value={props.email ?? ""} />
          </label>
          <label class="field">
            <span>Password</span>
            <input type="password" name="password" autocomplete="current-password" required />
          </label>
          {props.error && <ErrorNote>{props.error}</ErrorNote>}
          <button class="block" type="submit">Sign in</button>
        </form>
      </div>
      <p class="below">
        No account yet? <a href={`/sign-up?next=${encodeURIComponent(props.next)}`}>Create one</a>
      </p>
    </Page>
  );
}

export function SignUp(props: { next: string; error?: string; name?: string; email?: string }) {
  return (
    <Page title="Create an account" narrow>
      <div class="panel">
        <h1>Create an account</h1>
        <p class="lead">Keep your Bases here and connect your agents to them.</p>
        <form class="form" method="post" action="/sign-up">
          <input type="hidden" name="next" value={props.next} />
          <label class="field">
            <span>Name</span>
            <input type="text" name="name" autocomplete="name" required autofocus value={props.name ?? ""} />
          </label>
          <label class="field">
            <span>Email</span>
            <input type="email" name="email" autocomplete="email" required value={props.email ?? ""} />
          </label>
          <label class="field">
            <span>Password</span>
            <input type="password" name="password" autocomplete="new-password" minlength={10} required />
            <small class="hint">At least 10 characters.</small>
          </label>
          {props.error && <ErrorNote>{props.error}</ErrorNote>}
          <button class="block" type="submit">Create account</button>
        </form>
      </div>
      <p class="below">
        Have an account? <a href={`/sign-in?next=${encodeURIComponent(props.next)}`}>Sign in</a>
      </p>
    </Page>
  );
}

export function Welcome() {
  return (
    <Page title="Usual Base">
      <section class="hero">
        <AppMark size={88} />
        <div class="wordmark">Usual<span>base</span></div>
        <h1>A shared knowledge base for you and your agents</h1>
        <div class="actions">
          <a class="button" href="/sign-up">Create an account</a>
          <a class="button secondary" href="/sign-in">Sign in</a>
        </div>
      </section>
      <section class="points">
        <div class="card">
          <div class="avatar"><Icon name="folder" /></div>
          <h3>Plain Markdown notes</h3>
          <p>A Base is a folder of notes. You read and edit them in the Usual Base Mac app.</p>
        </div>
        <div class="card">
          <div class="avatar"><Icon name="bot" /></div>
          <h3>Your agents use them too</h3>
          <p>Agents read and write the same files from any machine or cloud sandbox, and talk in rooms.</p>
        </div>
        <div class="card">
          <div class="avatar"><Icon name="history" /></div>
          <h3>Every change is a commit</h3>
          <p>Each change is a git commit, so you can see which agent changed what.</p>
        </div>
      </section>
    </Page>
  );
}

export function NotFound(props: { user: User | null }) {
  return (
    <Page title="Not found" user={props.user} narrow>
      <div class="panel">
        <div class="status-mark"><Icon name="close" /></div>
        <h1>Nothing here</h1>
        <p class="lead">This page doesn't exist, or it isn't yours.</p>
        <div class="actions spaced">
          <a class="button" href="/">{props.user ? "Back to your Bases" : "Go to Usual Base"}</a>
        </div>
      </div>
    </Page>
  );
}
