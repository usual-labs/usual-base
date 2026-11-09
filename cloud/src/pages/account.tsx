import { Page } from "./layout";

export function SignIn(props: { next: string; error?: string; email?: string }) {
  return (
    <Page title="Sign in">
      <h1>Sign in</h1>
      <form class="stack" method="post" action="/sign-in">
        <input type="hidden" name="next" value={props.next} />
        <label>Email<input type="email" name="email" autocomplete="email" required value={props.email ?? ""} /></label>
        <label>Password<input type="password" name="password" autocomplete="current-password" required /></label>
        {props.error && <p class="error">{props.error}</p>}
        <div><button type="submit">Sign in</button></div>
      </form>
      <p class="muted">
        No account yet? <a href={`/sign-up?next=${encodeURIComponent(props.next)}`}>Create one</a>.
      </p>
    </Page>
  );
}

export function SignUp(props: { next: string; error?: string; name?: string; email?: string }) {
  return (
    <Page title="Create an account">
      <h1>Create an account</h1>
      <form class="stack" method="post" action="/sign-up">
        <input type="hidden" name="next" value={props.next} />
        <label>Name<input type="text" name="name" autocomplete="name" required value={props.name ?? ""} /></label>
        <label>Email<input type="email" name="email" autocomplete="email" required value={props.email ?? ""} /></label>
        <label>
          Password (at least 10 characters)
          <input type="password" name="password" autocomplete="new-password" minlength={10} required />
        </label>
        {props.error && <p class="error">{props.error}</p>}
        <div><button type="submit">Create account</button></div>
      </form>
      <p class="muted">
        Have an account? <a href={`/sign-in?next=${encodeURIComponent(props.next)}`}>Sign in</a>.
      </p>
    </Page>
  );
}

export function Welcome() {
  return (
    <Page title="Usual Base">
      <h1>A shared knowledge base for you and your agents</h1>
      <p>
        Usual Base is a folder of Markdown notes that you read in the Mac app and your agents read and write as
        plain files, from any machine or cloud sandbox. Every change is a git commit, so you can see which agent
        changed what.
      </p>
      <p>
        <a class="button" href="/sign-up">Create an account</a>{" "}
        <a class="button secondary" href="/sign-in">Sign in</a>
      </p>
    </Page>
  );
}
