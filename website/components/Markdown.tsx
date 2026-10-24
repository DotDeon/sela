import { Fragment } from "react";

// Release notes use a small slice of Markdown: paragraphs, lines that are all
// bold as headings, lists, bold and inline code. This renders that slice and
// nothing else, so the notes can't inject markup into the page.

type Block =
  | { kind: "heading"; text: string }
  | { kind: "paragraph"; text: string }
  | { kind: "list"; ordered: boolean; items: string[] };

function blocks(source: string): Block[] {
  const out: Block[] = [];
  for (const line of source.replace(/\r\n/g, "\n").split("\n")) {
    const text = line.trim();
    if (!text) continue;
    const bullet = text.match(/^[-*]\s+(.*)$/);
    const numbered = text.match(/^\d+\.\s+(.*)$/);
    const item = bullet?.[1] ?? numbered?.[1];
    if (item !== undefined) {
      const ordered = Boolean(numbered);
      const last = out.at(-1);
      if (last?.kind === "list" && last.ordered === ordered) last.items.push(item);
      else out.push({ kind: "list", ordered, items: [item] });
      continue;
    }
    const heading = text.match(/^\*\*([^*]+)\*\*$/) ?? text.match(/^#{1,6}\s+(.*)$/);
    if (heading) out.push({ kind: "heading", text: heading[1] });
    else out.push({ kind: "paragraph", text });
  }
  return out;
}

function inline(text: string) {
  return text.split(/(\*\*[^*]+\*\*|`[^`]+`)/g).map((part, i) => {
    if (part.startsWith("**") && part.endsWith("**")) return <strong key={i}>{part.slice(2, -2)}</strong>;
    if (part.startsWith("`") && part.endsWith("`")) return <code key={i}>{part.slice(1, -1)}</code>;
    return <Fragment key={i}>{part}</Fragment>;
  });
}

export function Markdown({ source }: { source: string }) {
  return (
    <div className="prose">
      {blocks(source).map((block, i) => {
        if (block.kind === "heading") return <h3 key={i}>{inline(block.text)}</h3>;
        if (block.kind === "paragraph") return <p key={i}>{inline(block.text)}</p>;
        const List = block.ordered ? "ol" : "ul";
        return (
          <List key={i}>
            {block.items.map((item, j) => (
              <li key={j}>{inline(item)}</li>
            ))}
          </List>
        );
      })}
    </div>
  );
}
