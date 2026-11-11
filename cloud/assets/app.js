// The dashboard works without this script; it only adds conveniences: copy buttons beside prompts, commands and
// tokens, and a question before a form that can't be undone (forms with data-confirm).

document.addEventListener("click", async (event) => {
  const button = event.target.closest(".copy button");
  if (!button) return;
  const pre = button.closest(".copy").querySelector("pre");
  const label = button.querySelector("span");
  const was = label.textContent;
  let copied = false;
  try {
    await navigator.clipboard.writeText(pre.innerText);
    copied = true;
  } catch {
    // No clipboard access (an older browser, or a page without focus): select the text, so copying is one keystroke.
    const range = document.createRange();
    range.selectNodeContents(pre);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    copied = document.execCommand?.("copy") ?? false;
  }
  label.textContent = copied ? "Copied" : "Selected";
  button.classList.toggle("done", copied);
  setTimeout(() => {
    label.textContent = was;
    button.classList.remove("done");
  }, 1600);
});

document.addEventListener("submit", (event) => {
  const question = event.target.dataset?.confirm;
  if (question && !confirm(question)) event.preventDefault();
});
