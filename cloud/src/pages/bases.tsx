import type { Base, PushRecord } from "../bases";
import type { User } from "../env";
import { AppMark, CopyBlock, ErrorNote, Icon, Page, PageHead, when } from "./layout";

export function BaseList(props: { user: User; bases: Base[] }) {
  return (
    <Page title="Bases" user={props.user} active="bases">
      <PageHead
        title="Bases"
        actions={props.bases.length > 0 && <a class="button" href="/bases/new"><Icon name="plus" size={16} />New Base</a>}
      >
        Folders of Markdown notes you share with your agents.
      </PageHead>
      {props.bases.length === 0 ? (
        <div class="empty">
          <AppMark size={56} />
          <h2>No Bases yet</h2>
          <p>
            A Base is a folder of Markdown notes shared with your agents. Start an empty one, or make a folder of notes
            you already have into a Base with the CLI: <code>usual-base init ./notes</code>.
          </p>
          <div class="actions spaced">
            <a class="button" href="/bases/new"><Icon name="plus" size={16} />New Base</a>
            <a class="button secondary" href="/agents/connect">Connect an agent</a>
          </div>
        </div>
      ) : (
        <div class="tiles">
          {props.bases.map((base) => (
            <a class="tile" href={`/bases/${base.id}`}>
              <span class="name">{base.name}</span>
              <span class="sub">
                <span>{base.lastPushAt ? `Changed ${when(base.lastPushAt)} by ${base.lastPushBy}` : "No changes yet"}</span>
                <Icon class="chev" name="chevron" size={16} />
              </span>
            </a>
          ))}
        </div>
      )}
    </Page>
  );
}

export function NewBase(props: { user: User; error?: string }) {
  return (
    <Page title="New Base" user={props.user} active="bases" narrow>
      <a class="crumb" href="/"><Icon name="back" size={16} />Bases</a>
      <div class="panel">
        <h1>New Base</h1>
        <p class="lead">An empty Base, ready for notes from you and your agents.</p>
        <form class="form" method="post" action="/bases">
          <label class="field">
            <span>Name</span>
            <input type="text" name="name" required maxlength={80} placeholder="Notes" autofocus />
          </label>
          {props.error && <ErrorNote>{props.error}</ErrorNote>}
          <button class="block" type="submit">Create Base</button>
        </form>
      </div>
    </Page>
  );
}

export function BaseDetail(props: { user: User; base: Base; git: string; pushes: PushRecord[]; error?: string }) {
  const { base } = props;
  return (
    <Page title={base.name} user={props.user} active="bases">
      <PageHead title={base.name} back={{ href: "/", label: "Bases" }}>
        Created {when(base.createdAt)} · last change {when(base.lastPushAt)}
      </PageHead>

      <section class="section">
        <header><h2>Open it</h2></header>
        <div class="card">
          <ul class="rows">
            <li class="row">
              <span class="avatar"><Icon name="laptop" /></span>
              <span class="grow">
                <span class="title">Mac app</span>
                <span class="sub">Sign in, and the Base appears in the sidebar.</span>
              </span>
            </li>
            <li>
              <a class="row" href="/agents/connect">
                <span class="avatar"><Icon name="bot" /></span>
                <span class="grow">
                  <span class="title">Agents</span>
                  <span class="sub">Connect an agent; it clones every Base its connection allows.</span>
                </span>
                <Icon class="chev" name="chevron" size={16} />
              </a>
            </li>
            <li class="row stacked">
              <span class="line">
                <span class="avatar"><Icon name="git" /></span>
                <span class="grow">
                  <span class="title">Git</span>
                  <span class="sub">Clone it with a Usual Base token as the password.</span>
                </span>
              </span>
              <CopyBlock text={`git clone ${props.git}`} label="Copy the clone command" class="indent" />
            </li>
          </ul>
        </div>
      </section>

      <section class="section">
        <header>
          <h2>Recent pushes</h2>
          {props.pushes.length > 0 && <p>Newest first</p>}
        </header>
        {props.pushes.length === 0 ? (
          <div class="empty"><p>Nothing pushed yet. Changes from the Mac app and your agents show up here.</p></div>
        ) : (
          <div class="card">
            <ul class="rows compact">
              {props.pushes.map((push) => (
                <li class="row">
                  <span class="grow title">{push.tokenName}</span>
                  <code>{push.newId.slice(0, 7)}</code>
                  <span class="when">{when(push.at)}</span>
                </li>
              ))}
            </ul>
          </div>
        )}
      </section>

      <section class="section">
        <header><h2>Settings</h2></header>
        <div class="card pad">
          <form class="inline-form" method="post" action={`/bases/${base.id}/rename`}>
            <label class="field">
              <span>Name</span>
              <input type="text" name="name" required maxlength={80} value={base.name} />
            </label>
            <button class="secondary" type="submit">Rename</button>
          </form>
        </div>
      </section>

      <section class="section">
        <div class="card pad danger-zone">
          <h2>Delete this Base</h2>
          <p class="muted">Deletes its notes and all their history, for you and every agent. This can't be undone.</p>
          <form class="inline-form" method="post" action={`/bases/${base.id}/delete`}>
            <label class="field">
              <span>Type “{base.name}” to confirm</span>
              <input type="text" name="confirm" required autocomplete="off" />
            </label>
            <button class="danger solid" type="submit">Delete Base</button>
          </form>
          {props.error && <ErrorNote>{props.error}</ErrorNote>}
        </div>
      </section>
    </Page>
  );
}
